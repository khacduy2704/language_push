import SwiftUI

struct SavedWordDetailView: View {
    let word: SavedWord
    @EnvironmentObject private var library: WordLibrary
    @State private var current: SavedWord?
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let current {
                    Text(current.word).font(.largeTitle).bold()
                    Text(current.partOfSpeech).font(.headline)
                    PronunciationControlsView(word: current.word)
                    if current.meaning.isEmpty {
                        Text("No meaning saved.")
                    } else {
                        Text(verbatim: current.meaning)
                    }
                    Text("Practice score: \(current.practiceScore)/5")
                        .accessibilityIdentifier("wordPracticeScore")
                    Text("Correct answers: \(current.correctAnswers)")
                    Text("Incorrect answers: \(current.incorrectAnswers)")
                    HStack(alignment: .top, spacing: 16) {
                        PushMembershipButton(word: current)
                        Button(LocalizedStringKey(current.isMastered ? "Learn Again" : "Mark as Mastered")) {
                            saving = true
                            Task {
                                do {
                                    try await library.setMastered(id: current.id, mastered: !current.isMastered)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                saving = false
                            }
                        }
                        .accessibilityIdentifier("wordMastery")
                    }
                    .buttonStyle(.bordered)
                    .disabled(saving)
                    Text(LocalizedStringKey(current.isMastered
                         ? "Learn Again moves this word to To Learn with 0 points. Add it to the push list again if needed."
                         : "Mastered words move to Mastered and are removed from the push list."))
                        .font(.footnote).foregroundColor(.secondary)
                } else if errorMessage == nil {
                    ProgressView("Loading word...")
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(word.word)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: library.revision) {
            do {
                let loaded = try await library.store.word(id: word.id)
                try Task.checkCancellation()
                current = loaded
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                current = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}
