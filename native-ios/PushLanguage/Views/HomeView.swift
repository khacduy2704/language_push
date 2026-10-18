import SwiftUI

struct HomeView: View {
    @State private var selectedTab: AppTab = .world
    @State private var dictionary = DictionaryStore()
    @StateObject private var library: WordLibrary
    @StateObject private var reminders: ReminderController
    @StateObject private var settings: AppSettings
    @StateObject private var auth: AuthController
    @Environment(\.scenePhase) private var scenePhase

    init(store: WordStore = WordStore()) {
        _auth = StateObject(wrappedValue: FirebaseAuthenticationClient.prepare())
        _library = StateObject(wrappedValue: WordLibrary(store: store))
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["PUSH_LANGUAGE_TEST_DATABASE_ID"],
           UUID(uuidString: id) != nil {
            guard let defaults = UserDefaults(suiteName: "ui-test-\(id)") else {
                preconditionFailure("Could not create isolated UI-test preferences.")
            }
            _reminders = StateObject(wrappedValue: ReminderController(
                store: store, center: UITestReminderCenter(), defaults: defaults
            ))
            _settings = StateObject(wrappedValue: AppSettings(defaults: defaults))
            return
        }
        #endif
        _reminders = StateObject(wrappedValue: ReminderController(store: store))
        _settings = StateObject(wrappedValue: AppSettings())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationView {
                    Group {
                        if tab == .world {
                            WorldView()
                        } else if tab == .search {
                            DictionarySearchView(dictionary: dictionary)
                        } else if tab == .pushList {
                            PushListView()
                        } else {
                            SettingsView()
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        if reminders.needsPermissionReminder {
                            NotificationPermissionReminderView()
                        }
                    }
                    .navigationTitle(Text(verbatim: AppLocalization.text(tab.title, language: settings.language)))
                }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label(LocalizedStringKey(tab.title), systemImage: tab.symbol)
                }
                .tag(tab)
            }
        }
        .accentColor(.blue)
        .task(id: library.revision) { await reminders.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await reminders.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await reminders.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await reminders.refresh() }
        }
        .safeAreaInset(edge: .top) {
            if let error = reminders.errorMessage {
                Text(error).font(.footnote).foregroundColor(.red).padding(8)
            }
        }
        .environmentObject(library)
        .environmentObject(reminders)
        .environmentObject(settings)
        .environmentObject(auth)
        .environment(\.locale, Locale(identifier: settings.language.rawValue))
    }
}
