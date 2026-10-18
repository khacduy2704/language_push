import Combine
import Foundation

@MainActor
final class ReminderController: ObservableObject {
    @Published private(set) var words: [SavedWord] = []
    @Published private(set) var status = "Checking reminders..."
    @Published private(set) var errorMessage: String?
    @Published private(set) var permission: ReminderPermission = .notDetermined
    @Published private(set) var hasCheckedPermission = false
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var interval: Int
    @Published private(set) var wordsPerReminder: Int
    @Published private(set) var timeWindow: ReminderTimeWindow
    private let store: WordStore
    private let center: ReminderCenter
    private let defaults: UserDefaults
    private var invalidWordCountPreference = false
    private var invalidTimeWindowPreference = false
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var tail: Task<Void, Never>?

    var needsPermissionReminder: Bool {
        hasCheckedPermission && permission != .allowed
    }

    init(
        store: WordStore, center: ReminderCenter = AppleReminderCenter(), defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { ReminderTimeWindow.localCalendar }
    ) {
        self.store = store
        self.center = center
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        let saved = defaults.object(forKey: "reminderIntervalMinutes") as? Int
        interval = saved ?? 10
        let savedWordCount = defaults.object(forKey: "reminderWordsPerNotification")
        wordsPerReminder = savedWordCount as? Int ?? 5
        invalidWordCountPreference = savedWordCount != nil && !(savedWordCount is Int)
        do {
            timeWindow = try ReminderTimeWindow.load(from: defaults)
        } catch {
            timeWindow = .standard
            invalidTimeWindowPreference = true
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        let previous = tail
        let next = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.rebuild()
        }
        tail = next
        await next.value
    }

    func enable() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        do {
            guard try await center.requestPermission() else { throw ReminderError.permissionDenied }
            await refresh()
        } catch {
            permission = await center.permission()
            hasCheckedPermission = true
            errorMessage = error.localizedDescription
            status = AppLocalization.text("Reminders are not enabled.")
        }
    }

    func setInterval(_ value: Int) async {
        guard ReminderPlan.intervals.contains(value) else {
            errorMessage = ReminderError.invalidInterval.localizedDescription
            return
        }
        interval = value
        defaults.set(value, forKey: "reminderIntervalMinutes")
        await refresh()
    }

    func setWordsPerReminder(_ value: Int) async {
        guard ReminderPlan.wordCounts.contains(value) else {
            errorMessage = ReminderError.invalidWordCount.localizedDescription
            return
        }
        wordsPerReminder = value
        invalidWordCountPreference = false
        defaults.set(value, forKey: "reminderWordsPerNotification")
        await refresh()
    }

    @discardableResult
    func setTimeWindow(_ value: ReminderTimeWindow) async -> Bool {
        do {
            let validated = try value.validated()
            let data = try JSONEncoder().encode(validated)
            defaults.set(data, forKey: ReminderTimeWindow.preferenceKey)
            timeWindow = validated
            invalidTimeWindowPreference = false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        await refresh()
        return true
    }

    private func rebuild() async {
        errorMessage = nil
        status = "Updating reminders..."
        let owned = (1...50).map { ReminderPlan.prefix + String($0) }
        // Cancel stale content even if reading the database or validating settings fails.
        await center.remove(identifiers: owned)
        permission = await center.permission()
        hasCheckedPermission = true
        do {
            words = try await store.words().filter(\.isPushed)
            guard !invalidWordCountPreference else { throw ReminderError.invalidWordCount }
            guard !invalidTimeWindowPreference else { throw ReminderError.invalidTimeWindow }
            let calendar = calendar()
            let plan = try ReminderPlan(
                words: words, interval: interval, wordsPerReminder: wordsPerReminder,
                timeWindow: timeWindow, now: now(), calendar: calendar
            )
            guard !words.isEmpty else {
                status = "No words selected for push yet."
                return
            }
            guard permission == .allowed else {
                status = permission == .denied
                    ? "Notifications are disabled in iOS Settings."
                    : "Enable notifications to schedule reminders."
                return
            }
            let other = await center.pendingIdentifiers().filter { !$0.hasPrefix(ReminderPlan.prefix) }
            guard other.count + plan.delays.count <= 64 else { throw ReminderError.insufficientCapacity }
            for (index, date) in plan.dates.enumerated() {
                guard date > now() else { throw ReminderError.incompleteSchedule }
                try await center.add(id: owned[index], body: plan.bodies[index], date: date, calendar: calendar)
            }
            let retained = Set(await center.pendingIdentifiers())
            guard Set(owned).isSubset(of: retained) else { throw ReminderError.incompleteSchedule }
            status = AppLocalization.format("50 reminders scheduled, every %d min.", interval)
        } catch {
            await center.remove(identifiers: owned)
            errorMessage = AppLocalization.format("Could not schedule reminders. %@", error.localizedDescription)
            status = "No reminders scheduled. Your saved push selection is unchanged."
        }
    }
}
