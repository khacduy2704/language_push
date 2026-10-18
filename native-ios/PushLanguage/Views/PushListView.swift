import SwiftUI

struct PushListView: View {
    @EnvironmentObject private var library: WordLibrary
    @EnvironmentObject private var reminders: ReminderController
    @State private var candidate: SavedWord?
    @State private var confirmRemoval = false
    @State private var errorMessage: String?
    @State private var removing = false
    @State private var updatingInterval = false
    @State private var practiceSession: PracticeSession?
    @State private var showingPractice = false
    @State private var preparingPractice = false
    @State private var settingsExpanded = false

    var body: some View {
        List {
            reminderSettings
            pushWords
        }
        .listStyle(.plain)
        .accessibilityIdentifier("pushWordList")
        .disabled(removing)
        .background(
            NavigationLink(isActive: $showingPractice) {
                if let practiceSession { PracticeView(session: practiceSession) }
            } label: { EmptyView() }
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Practice") {
                    preparingPractice = true
                    errorMessage = nil
                    Task {
                        do {
                            let words = try await library.store.words().filter(\.isPushed)
                            practiceSession = try PracticeSession(words: words)
                            showingPractice = true
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        preparingPractice = false
                    }
                }
                .disabled(preparingPractice || removing)
                .accessibilityIdentifier("startPractice")
            }
        }
        .alert("Remove from Push List", isPresented: $confirmRemoval, presenting: candidate) { word in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removing = true
                Task {
                    do {
                        try await library.setPushed(id: word.id, pushed: false)
                    } catch {
                        errorMessage = AppLocalization.format("Could not remove word. %@", error.localizedDescription)
                    }
                    removing = false
                }
            }
        } message: { word in
            Text("Remove \"\(word.word)\" from reminders? The word stays in World.")
        }
    }

    private var reminderSettings: some View {
        Section {
            Button {
                withAnimation { settingsExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Reminder settings", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                        Text("\(reminders.interval) min · \(reminders.wordsPerReminder) words")
                            .font(.caption).foregroundColor(.secondary)
                        if reminders.timeWindow.enabled {
                            Text(verbatim: reminders.timeWindow.hoursSummary)
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("All day").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pushSettingsToggle")
            .accessibilityValue(Text(LocalizedStringKey(settingsExpanded ? "Expanded" : "Collapsed")))
            .accessibilityHint(Text("Show or hide reminder settings."))
            if let error = errorMessage ?? reminders.errorMessage {
                Text(error).foregroundColor(.red)
            }
            Text(LocalizedStringKey(reminders.status)).accessibilityIdentifier("reminderStatus")
                .font(.footnote).foregroundColor(.secondary)
            if settingsExpanded {
                expandedSettings
            }
        }
    }

    private var expandedSettings: some View {
        Group {
            Picker("Reminder interval", selection: Binding(
                get: { reminders.interval },
                set: { value in
                    updatingInterval = true
                    Task {
                        await reminders.setInterval(value)
                        updatingInterval = false
                    }
                }
            )) {
                ForEach(ReminderPlan.intervals, id: \.self) { value in
                    Text("\(value) min").tag(value)
                }
            }
            .disabled(updatingInterval)
            .accessibilityIdentifier("reminderInterval")
            ReminderWordCountPicker()
            ReminderTimeWindowLink()
            Button("Refresh Reminders") { Task { await reminders.refresh() } }
                .buttonStyle(.bordered)
            Text("\(reminders.words.count) words in push list. Each reminder randomly selects up to \(reminders.wordsPerReminder) words.")
                .font(.footnote).foregroundColor(.secondary)
            Text("Reminders stop after 50 deliveries; reopen the app or refresh to rebuild.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private var pushWords: some View {
        Section {
            ForEach(reminders.words) { word in
                NavigationLink(destination: SavedWordDetailView(word: word)) {
                    VStack(alignment: .leading) {
                        Text(word.word).font(.headline)
                        Text("(\(word.partOfSpeech)) \(word.meaning)").font(.subheadline)
                    }
                }
                .accessibilityIdentifier("pushWord-\(word.id)")
                .swipeActions(allowsFullSwipe: false) {
                    Button("Remove", role: .destructive) {
                        candidate = word
                        confirmRemoval = true
                    }
                }
            }
        } header: {
            Text("Push words (\(reminders.words.count))")
        } footer: {
            Text("Home-screen widgets are not migrated yet.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}
