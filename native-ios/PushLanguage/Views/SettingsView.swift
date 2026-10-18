import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminders: ReminderController
    @EnvironmentObject private var library: WordLibrary
    @EnvironmentObject private var auth: AuthController
    @State private var updatingInterval = false
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                if let account = auth.account {
                    Text(verbatim: account.email ?? AppLocalization.text("No email"))
                    Text(verbatim: account.displayName ?? AppLocalization.text("No display name"))
                    Text(verbatim: "UID: \(account.uid)")
                        .textSelection(.enabled)
                        .accessibilityIdentifier("accountUID")
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                        .disabled(auth.busy)
                } else if auth.configured {
                    NavigationLink {
                        AuthenticationView()
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("settingsSignIn")
                } else {
                    Text("Firebase setup is required for this native app.")
                        .accessibilityIdentifier("authSetupRequired")
                    if let message = auth.setupMessage {
                        Text(LocalizedStringKey(message)).font(.footnote).foregroundColor(.red)
                    }
                }
                if let error = auth.errorMessage { Text(error).foregroundColor(.red) }
                Text("Saved words remain local to this app. Signing in does not upload or separate them by account.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .alert("Sign Out", isPresented: $confirmSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) { auth.signOut() }
            } message: {
                Text("Sign out of this account? Local words and reminders remain on this device.")
            }
            Section(header: Text("Common")) {
                Picker("Language", selection: Binding(
                    get: { settings.language },
                    set: { value in
                        settings.setLanguage(value)
                        Task { await reminders.refresh() }
                    }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language)
                    }
                }
                .accessibilityIdentifier("settingsLanguage")
                if let error = settings.errorMessage {
                    Text(LocalizedStringKey(error)).foregroundColor(.red)
                }
                Picker("Time to push", selection: Binding(
                    get: { reminders.interval },
                    set: { value in
                        updatingInterval = true
                        Task {
                            await reminders.setInterval(value)
                            updatingInterval = false
                        }
                    }
                )) {
                    ForEach(ReminderPlan.intervals, id: \.self) { interval in
                        Text("\(interval) min").tag(interval)
                    }
                }
                .disabled(updatingInterval)
                .accessibilityIdentifier("settingsInterval")
                ReminderWordCountPicker()
                ReminderTimeWindowLink()
                Text(LocalizedStringKey(reminders.status))
                    .font(.footnote)
                    .accessibilityIdentifier("settingsReminderStatus")
                if let error = reminders.errorMessage {
                    Text(error).foregroundColor(.red)
                }
            }
            Section(header: Text("Database")) {
                NavigationLink {
                    DatabaseLocationView(store: library.store)
                } label: {
                    Label("Database Location", systemImage: "internaldrive")
                }
                .accessibilityIdentifier("settingsDatabase")
            }
            Section(header: Text("Audio")) {
                Text("Apple text-to-speech (English US)")
                    .accessibilityIdentifier("settingsSpeech")
                Text("Recording downloads, cached audio management, and listening exercises are not migrated yet.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }
}

struct DatabaseLocationView: View {
    let store: WordStore
    @State private var path: String?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your custom words are stored here:")
                if let path {
                    Text(verbatim: path)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("databasePath")
                } else if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                    Button("Retry") { retry += 1 }
                } else {
                    ProgressView("Loading database location...")
                }
                Text("Dictionary data is read directly from the bundled .dict file.")
                Text("This is the native app's database. Existing Flutter data is not automatically imported.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Database Location")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retry) {
            do {
                let url = try await store.location()
                try Task.checkCancellation()
                path = url.path
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = AppLocalization.format("Could not locate the database. %@", error.localizedDescription)
            }
        }
    }
}
