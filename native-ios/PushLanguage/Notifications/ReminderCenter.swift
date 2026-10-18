import UserNotifications

enum ReminderPermission {
    case notDetermined
    case allowed
    case denied
}

protocol ReminderCenter {
    func permission() async -> ReminderPermission
    func requestPermission() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func remove(identifiers: [String]) async
    func add(id: String, body: String, date: Date, calendar: Calendar) async throws
}

final class AppleReminderCenter: ReminderCenter {
    private let center = UNUserNotificationCenter.current()

    func permission() async -> ReminderPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    static func trigger(date: Date, calendar: Calendar) -> UNCalendarNotificationTrigger {
        // Omit a fixed time zone so requests follow the device's local clock.
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    func add(id: String, body: String, date: Date, calendar: Calendar) async throws {
        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("Words to push")
        content.body = body
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: id, content: content,
            trigger: Self.trigger(date: date, calendar: calendar)
        ))
    }
}

final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

}

#if DEBUG
final class UITestReminderCenter: ReminderCenter {
    private var authorization: ReminderPermission = {
        switch ProcessInfo.processInfo.environment["PUSH_LANGUAGE_TEST_NOTIFICATION_PERMISSION"] {
        case "allowed": return .allowed
        case "notDetermined": return .notDetermined
        default: return .denied
        }
    }()
    private var identifiers: Set<String> = []

    func permission() async -> ReminderPermission { authorization }
    func requestPermission() async throws -> Bool {
        if authorization == .notDetermined { authorization = .allowed }
        return authorization == .allowed
    }
    func pendingIdentifiers() async -> [String] { Array(identifiers) }
    func remove(identifiers: [String]) async {
        self.identifiers.subtract(identifiers)
    }
    func add(id: String, body: String, date: Date, calendar: Calendar) async throws {
        guard authorization == .allowed else { throw ReminderError.permissionDenied }
        identifiers.insert(id)
    }
}
#endif
