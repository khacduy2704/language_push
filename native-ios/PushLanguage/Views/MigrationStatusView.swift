import SwiftUI

struct MigrationStatusView: View {
    let tab: AppTab

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)

                Text("Native migration in progress")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(tab.migrationMessage)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("migrationMessage")

                Text("Use the Flutter app for existing features. This separate app does not access or change its data.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
