import SwiftUI

struct PushMembershipButton: View {
    let word: SavedWord
    @EnvironmentObject private var library: WordLibrary
    @State private var saving = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading) {
            Button(LocalizedStringKey(word.isPushed ? "Remove from Push List" : "Add to Push List")) {
                saving = true
                message = nil
                Task {
                    do {
                        try await library.setPushed(id: word.id, pushed: !word.isPushed)
                    } catch {
                        message = error.localizedDescription
                    }
                    saving = false
                }
            }
            .disabled(saving || word.isMastered)
            .accessibilityIdentifier("pushMembership")
            if let message { Text(message).foregroundColor(.red) }
        }
    }
}
