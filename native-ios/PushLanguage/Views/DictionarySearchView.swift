import SwiftUI

struct DictionarySearchView: View {
    private enum Phase {
        case idle
        case loading
        case results(saved: [SavedWord], dictionary: [DictionaryEntry])
        case failed(String)
    }

    private struct Request: Equatable {
        let query: String
        let retry: Int
        let revision: Int
    }

    let dictionary: DictionaryStore
    @EnvironmentObject private var library: WordLibrary
    @State private var query = ""
    @State private var retry = 0
    @State private var phase: Phase = .idle

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search words", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .accessibilityIdentifier("dictionarySearchField")
                .padding()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Saved words appear first. Type at least 2 characters for offline dictionary results.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .task(id: Request(query: query, retry: retry, revision: library.revision)) {
            await search()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Text("Type at least 2 characters to search words")
                .foregroundColor(.secondary)
                .padding()
        case .loading:
            ProgressView("Searching offline dictionary...")
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message).multilineTextAlignment(.center)
                Button("Retry") { retry += 1 }
            }
            .padding()
        case .results(let saved, let entries):
            if saved.isEmpty && entries.isEmpty {
                Text(LocalizedStringKey(query.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count < 2
                     ? "Type at least 2 characters to search words" : "No words found"))
                    .foregroundColor(.secondary)
            } else {
                List {
                    if !saved.isEmpty {
                        Section(header: Text("Saved words")) {
                            ForEach(saved) { word in
                                NavigationLink(destination: SavedWordDetailView(word: word)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(word.word).font(.headline)
                                        Text("(\(word.partOfSpeech)) \(word.meaning)").font(.subheadline)
                                    }
                                }
                                .accessibilityIdentifier("searchSavedWord-\(word.id)")
                            }
                        }
                    }
                    if !entries.isEmpty {
                        Section(header: Text("Dictionary")) {
                            ForEach(entries) { entry in
                                NavigationLink(destination: DictionaryDetailView(entry: entry, dictionary: dictionary)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.word).font(.headline)
                                        if !entry.ipa.isEmpty {
                                            Text(entry.ipa).foregroundColor(.secondary)
                                        }
                                        if !entry.preview.isEmpty {
                                            Text(entry.preview).font(.subheadline).lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .accessibilityIdentifier("dictionaryResult-\(entry.id)")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @MainActor
    private func search() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .loading
        do {
            try await Task.sleep(nanoseconds: 280_000_000)
            let saved = try await library.store.words(query: normalized, includePushed: false)
            let entries = normalized.utf16.count >= 2
                ? try await dictionary.search(query: normalized) : []
            try Task.checkCancellation()
            phase = .results(saved: saved, dictionary: entries)
        } catch is CancellationError {
            // A newer query or leaving the screen cancels this request.
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(AppLocalization.format("Could not search the dictionary. %@", error.localizedDescription))
        }
    }
}
