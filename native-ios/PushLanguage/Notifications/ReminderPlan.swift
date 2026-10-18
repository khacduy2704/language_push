import Foundation

struct ReminderPlan {
    static let intervals = [1, 5, 10, 20, 30, 60, 120]
    static let wordCounts = [1, 2, 3, 4, 5]
    static let prefix = "push-language-reminder-"
    let batches: [[SavedWord]]
    let bodies: [String]
    let dates: [Date]
    let delays: [TimeInterval]

    init(
        words: [SavedWord], interval: Int, wordsPerReminder: Int = 5,
        timeWindow: ReminderTimeWindow = .standard, now: Date = Date(),
        calendar: Calendar = ReminderTimeWindow.localCalendar
    ) throws {
        var generator = SystemRandomNumberGenerator()
        try self.init(
            words: words, interval: interval, wordsPerReminder: wordsPerReminder,
            timeWindow: timeWindow, now: now, calendar: calendar, using: &generator
        )
    }

    init<R: RandomNumberGenerator>(
        words: [SavedWord], interval: Int, wordsPerReminder: Int,
        timeWindow: ReminderTimeWindow = .standard, now: Date = Date(),
        calendar: Calendar = ReminderTimeWindow.localCalendar, using generator: inout R
    ) throws {
        guard Self.intervals.contains(interval) else { throw ReminderError.invalidInterval }
        guard Self.wordCounts.contains(wordsPerReminder) else { throw ReminderError.invalidWordCount }
        let timeWindow = try timeWindow.validated()
        var dates: [Date] = []
        var previous = now
        if !words.isEmpty {
            for _ in 0..<50 {
                let candidate = previous.addingTimeInterval(TimeInterval(interval * 60))
                let next = try timeWindow.nextAllowedDate(onOrAfter: candidate, calendar: calendar)
                guard next > previous else { throw ReminderError.invalidScheduleDate }
                dates.append(next)
                previous = next
            }
        }
        self.dates = dates
        delays = dates.map { $0.timeIntervalSince(now) }
        batches = delays.map { _ in Array(words.shuffled(using: &generator).prefix(wordsPerReminder)) }
        bodies = batches.map { batch in
            batch.map {
                $0.meaning.isEmpty ? "\($0.word) (\($0.partOfSpeech))"
                    : "\($0.word) (\($0.partOfSpeech)) \($0.meaning)"
            }.joined(separator: "\n")
        }
    }
}

enum ReminderError: LocalizedError {
    case invalidInterval
    case invalidWordCount
    case invalidTimeWindow
    case invalidScheduleDate
    case insufficientCapacity
    case permissionDenied
    case incompleteSchedule

    var errorDescription: String? {
        switch self {
        case .invalidInterval: return AppLocalization.text("Choose a supported reminder interval.")
        case .invalidWordCount: return AppLocalization.text("Choose between 1 and 5 words per reminder.")
        case .invalidTimeWindow:
            return AppLocalization.text("Choose different start and end times between 00:00 and 23:59.")
        case .invalidScheduleDate:
            return AppLocalization.text("Could not calculate reminder dates. Check your time settings and retry.")
        case .insufficientCapacity:
            return AppLocalization.text("Other pending notifications leave insufficient capacity for 50 reminders.")
        case .permissionDenied:
            return AppLocalization.text("Notifications are disabled. Enable them in iOS Settings to receive reminders.")
        case .incompleteSchedule:
            return AppLocalization.text("iOS did not retain all 50 reminders. Refresh reminders to retry.")
        }
    }
}
