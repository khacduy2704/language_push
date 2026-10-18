import SwiftUI

struct WorldView: View {
    private struct Request: Equatable {
        let query: String
        let revision: Int
        let retry: Int
        let status: WordLearningStatus
    }

    private struct FormSelection: Identifiable {
        let id = UUID()
        let word: SavedWord?
    }

    @EnvironmentObject private var library: WordLibrary
    @State private var query = ""
    @State private var words: [SavedWord] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var form: FormSelection?
    @State private var deleteCandidate: SavedWord?
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var mutating = false
    @State private var learningStatus: WordLearningStatus = .learning

    var body: some View {
        VStack {
            Picker("Learning status", selection: $learningStatus) {
                ForEach(WordLearningStatus.allCases) { status in
                    Text(LocalizedStringKey(status.rawValue)).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("worldLearningStatus")
            .padding(.horizontal)
            TextField("Search saved words", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .accessibilityIdentifier("worldSearchField")
                .padding(.horizontal)

            if let errorMessage {
                VStack {
                    Text(errorMessage).foregroundColor(.red)
                    Button("Retry") { retry += 1 }
                }
                .padding()
            }
            if loading {
                ProgressView("Loading saved words...")
            } else if words.isEmpty && errorMessage == nil {
                Text(LocalizedStringKey(query.isEmpty
                    ? (learningStatus == .mastered ? "No mastered words yet." : "No saved words. Tap + to add a word.")
                    : "No words found."))
                    .foregroundColor(.secondary)
                    .padding()
            }
            List(words) { word in
                NavigationLink(destination: SavedWordDetailView(word: word)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(word.word).font(.headline)
                            Text("(\(word.partOfSpeech)) \(word.meaning)")
                                .font(.subheadline).foregroundColor(.secondary)
                            Text("Practice score: \(word.practiceScore)/5")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if word.isPushed {
                            Label("In Push List", systemImage: "bell.fill")
                                .labelStyle(.iconOnly)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .accessibilityIdentifier("savedWord-\(word.id)")
                .accessibilityValue(Text(LocalizedStringKey(word.isPushed ? "In Push List" : "Not in Push List")))
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        deleteCandidate = word
                        confirmDelete = true
                    }
                    Button("Edit") { form = FormSelection(word: word) }
                        .tint(.blue)
                }
                .contextMenu {
                    Button("Edit") { form = FormSelection(word: word) }
                    Button("Delete", role: .destructive) {
                        deleteCandidate = word
                        confirmDelete = true
                    }
                }
            }
            .listStyle(.plain)
            .disabled(mutating)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    confirmClear = true
                } label: {
                    Label("Remove All Words", systemImage: "trash")
                }
                .accessibilityIdentifier("clearAllWords")
                .disabled(mutating || loading)
                Button {
                    learningStatus = .learning
                    form = FormSelection(word: nil)
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
                .accessibilityIdentifier("addWord")
                .disabled(mutating)
            }
        }
        .sheet(item: $form) { selection in
            WordFormView(original: selection.word)
        }
        .alert("Delete Word", isPresented: $confirmDelete, presenting: deleteCandidate) { word in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                mutate { try await library.delete(id: word.id) }
            }
        } message: { word in
            Text("Delete \"\(word.word)\"?")
        }
        .alert("Remove All Words", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                mutate { try await library.clear() }
            }
        } message: {
            Text("Remove all saved words from To Learn and Mastered, including words outside the current search? This cannot be undone.")
        }
        .task(id: Request(query: query, revision: library.revision, retry: retry, status: learningStatus)) {
            loading = true
            errorMessage = nil
            do {
                let loaded = try await library.store.words(query: query, learningStatus: learningStatus)
                try Task.checkCancellation()
                words = loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                words = []
                errorMessage = AppLocalization.format("Could not load words. %@", error.localizedDescription)
            }
            loading = false
        }
    }

    private func mutate(_ operation: @escaping @MainActor () async throws -> Void) {
        mutating = true
        errorMessage = nil
        Task {
            do {
                try await operation()
            } catch {
                errorMessage = AppLocalization.format("Could not remove words. %@", error.localizedDescription)
            }
            mutating = false
        }
    }
}
