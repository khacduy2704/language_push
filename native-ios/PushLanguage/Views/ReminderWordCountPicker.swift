import SwiftUI

struct ReminderWordCountPicker: View {
    @EnvironmentObject private var reminders: ReminderController
    @State private var updating = false

    var body: some View {
        Picker("Words per reminder", selection: Binding(
            get: { reminders.wordsPerReminder },
            set: { value in
                updating = true
                Task {
                    await reminders.setWordsPerReminder(value)
                    updating = false
                }
            }
        )) {
            ForEach(ReminderPlan.wordCounts, id: \.self) { count in
                Text(verbatim: String(count)).tag(count)
            }
        }
        .disabled(updating)
        .accessibilityIdentifier("reminderWordCount")
    }
}
