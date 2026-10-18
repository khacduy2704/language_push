import SwiftUI

struct DictionaryDetailView: View {
    private enum Phase {
        case loading
        case loaded([DefinitionLine])
        case failed(String)
    }
    let entry: DictionaryEntry
    let dictionary: DictionaryStore
    @State private var phase: Phase = .loading
    @State private var retry = 0
    @EnvironmentObject private var library: WordLibrary
    @State private var savingMeaning = false
    @State private var saveMessage: String?
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.word).font(.largeTitle).fontWeight(.bold)
                if !entry.ipa.isEmpty {
                    Text(entry.ipa).font(.title3).foregroundColor(.secondary)
                }
                PronunciationControlsView(word: entry.word)
                if let saveMessage {
                    Text(saveMessage)
                        .foregroundColor(saveFailed ? .red : .secondary)
                        .accessibilityIdentifier("meaningSaveStatus")
                }
                switch phase {
                case .loading:
                    ProgressView("Loading definition...")
                case .failed(let message):
                    Text(message)
                    Button("Retry") { retry += 1 }
                case .loaded(let lines):
                    if lines.isEmpty {
                        Text("No definition text is available.")
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(line.kind == .heading ? .headline : .body)
                                    .foregroundColor(line.kind == .example ? .secondary : .primary)
                                    .padding(.top, line.kind == .heading ? 8 : 0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if line.kind == .meaning || line.kind == .note {
                                    Button("Save meaning to World") {
                                        saveMeaning(line)
                                    }
                                    .font(.caption)
                                    .disabled(savingMeaning)
                                    .accessibilityIdentifier("saveMeaning-\(line.id)")
                                }
                            }
                        }
                        .accessibilityIdentifier("dictionaryDefinition")
                    }
                }
                Divider()
                Text("Save a meaning to World, then open the saved word to add it to the push list.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(entry.word)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retry) {
            phase = .loading
            do {
                let meaning = try await dictionary.loadMeaning(for: entry)
                try Task.checkCancellation()
                phase = .loaded(DefinitionLine.parse(meaning))
            } catch is CancellationError {
                // Navigation away from the detail screen cancels loading.
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(AppLocalization.format("Could not load the definition. %@", error.localizedDescription))
            }
        }

    }

    private func saveMeaning(_ line: DefinitionLine) {
        savingMeaning = true
        saveMessage = nil
        Task {
            do {
                let inserted = try await library.saveMeaning(
                    WordDraft(word: entry.word, partOfSpeech: line.partOfSpeech, meaning: line.text)
                )
                saveFailed = false
                saveMessage = AppLocalization.text(inserted ? "Meaning saved to World." : "This meaning is already saved to World.")
            } catch {
                saveFailed = true
                saveMessage = AppLocalization.format("Could not save meaning. %@", error.localizedDescription)
            }
            savingMeaning = false
        }
    }
}
