import SwiftUI

struct NotificationPermissionReminderView: View {
    @EnvironmentObject private var reminders: ReminderController
    @Environment(\.openURL) private var openURL
    @State private var settingsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Allow notifications to receive word reminders.", systemImage: "bell.badge")
                .font(.subheadline)
                .accessibilityIdentifier("notificationPermissionReminder")
            if reminders.permission == .denied {
                Text("Notifications are disabled. Enable them in iOS Settings to receive reminders.")
                    .font(.footnote)
                Button("Open iOS Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else {
                        settingsError = true
                        return
                    }
                    openURL(url) { accepted in settingsError = !accepted }
                }
                .accessibilityIdentifier("notificationPermissionSettings")
            } else {
                Button("Enable Notifications") {
                    Task { await reminders.enable() }
                }
                .disabled(reminders.isRequestingPermission)
                .accessibilityIdentifier("notificationPermissionEnable")
            }
            if settingsError {
                Text("Could not open iOS Settings. Open Settings manually and allow notifications for this app.")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.yellow.opacity(0.15))
    }
}
