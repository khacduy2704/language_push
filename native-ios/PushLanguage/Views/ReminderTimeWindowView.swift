import SwiftUI

struct ReminderTimeWindowLink: View {
    @EnvironmentObject private var reminders: ReminderController

    var body: some View {
        NavigationLink {
            ReminderTimeWindowView(timeWindow: reminders.timeWindow)
        } label: {
            HStack {
                Label("Reminder hours", systemImage: "clock")
                Spacer()
                if reminders.timeWindow.enabled {
                    Text(verbatim: reminders.timeWindow.hoursSummary)
                        .foregroundColor(.secondary)
                } else {
                    Text("All day").foregroundColor(.secondary)
                }
            }
            .font(.subheadline)
        }
        .accessibilityIdentifier("reminderTimeWindow")
    }
}

struct ReminderTimeWindowView: View {
    @EnvironmentObject private var reminders: ReminderController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReminderTimeWindow
    @State private var saving = false
    @State private var errorMessage: String?

    init(timeWindow: ReminderTimeWindow) {
        _draft = State(initialValue: timeWindow)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Limit reminder hours", isOn: $draft.enabled)
                    .accessibilityIdentifier("reminderHoursEnabled")
            } footer: {
                Text("When off, reminders can arrive at any time.")
            }
            if draft.enabled {
                Section(header: Text("Start time")) {
                    timePickers(minutes: $draft.startMinute, prefix: "reminderStart")
                }
                Section(header: Text("End time")) {
                    timePickers(minutes: $draft.endMinute, prefix: "reminderEnd")
                }
                Section {
                    Text("Uses local device time. Reminders start at the opening time and stop before the end time.")
                    Text("If the end time is earlier than the start time, the window continues into the next day.")
                    Text("Reminders outside this window move to the next opening time, then continue at the selected interval.")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundColor(.red)
                        .accessibilityIdentifier("reminderHoursError")
                }
            }
        }
        .disabled(saving)
        .navigationTitle("Reminder hours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saving = true
                    Task {
                        if await reminders.setTimeWindow(draft) {
                            dismiss()
                        } else {
                            errorMessage = reminders.errorMessage
                        }
                        saving = false
                    }
                }
                .disabled(saving)
                .accessibilityIdentifier("reminderHoursSave")
            }
        }
    }

    private func timePickers(minutes: Binding<Int>, prefix: String) -> some View {
        HStack {
            Picker("Hour", selection: Binding(
                get: { minutes.wrappedValue / 60 },
                set: { minutes.wrappedValue = $0 * 60 + minutes.wrappedValue % 60 }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(verbatim: String(format: "%02d", hour)).tag(hour)
                }
            }
            .accessibilityIdentifier(prefix + "Hour")
            Picker("Minute", selection: Binding(
                get: { minutes.wrappedValue % 60 },
                set: { minutes.wrappedValue = minutes.wrappedValue / 60 * 60 + $0 }
            )) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(verbatim: String(format: "%02d", minute)).tag(minute)
                }
            }
            .accessibilityIdentifier(prefix + "Minute")
        }
        .pickerStyle(.menu)
    }
}
