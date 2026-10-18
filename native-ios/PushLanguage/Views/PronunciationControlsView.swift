import SwiftUI

struct PronunciationControlsView: View {
    let word: String
    @StateObject private var pronunciation = PronunciationService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Button {
                    pronunciation.play(word, speed: .normal)
                } label: {
                    Label("Pronounce", systemImage: "speaker.wave.2")
                }
                .accessibilityIdentifier("pronounceNormal")

                Button {
                    pronunciation.play(word, speed: .slow)
                } label: {
                    Label("Slow", systemImage: "tortoise")
                }
                .accessibilityIdentifier("pronounceSlow")

                Button("Stop") { pronunciation.stop() }
                    .accessibilityIdentifier("pronounceStop")
                    .disabled(!isSpeaking)
            }
            switch pronunciation.state {
            case .idle:
                Text("Apple text-to-speech (English US)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            case .speaking(let speed):
                Text(LocalizedStringKey(speed == .slow ? "Speaking slowly..." : "Speaking..."))
                    .font(.footnote)
                    .accessibilityIdentifier("pronunciationStatus")
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("pronunciationError")
            }
        }
        .buttonStyle(.bordered)
        .onDisappear { pronunciation.stop() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { pronunciation.stop() }
        }
    }

    private var isSpeaking: Bool {
        if case .speaking = pronunciation.state { return true }
        return false
    }
}
