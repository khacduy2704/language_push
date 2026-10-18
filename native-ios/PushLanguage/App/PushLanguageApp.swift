import SwiftUI
import UserNotifications

@main
struct PushLanguageApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = ForegroundNotificationDelegate.shared
    }
    private let store: WordStore = {
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["PUSH_LANGUAGE_TEST_DATABASE_ID"] {
            guard UUID(uuidString: id) != nil else {
                preconditionFailure("The UI test database identifier must be a UUID.")
            }
            return WordStore(databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ui-test-\(id).db"))
        }
        #endif
        return WordStore()
    }()

    var body: some Scene {
        WindowGroup {
            HomeView(store: store)
        }
    }
}
