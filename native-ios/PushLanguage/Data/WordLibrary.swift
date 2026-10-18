import Combine

@MainActor
final class WordLibrary: ObservableObject {
    let store: WordStore
    @Published private(set) var revision = 0

    init(store: WordStore = WordStore()) {
        self.store = store
    }

    func save(_ draft: WordDraft, id: Int64? = nil) async throws {
        if let id {
            try await store.update(id: id, draft: draft)
        } else {
            _ = try await store.add(draft)
        }
        revision += 1
    }

    func saveMeaning(_ draft: WordDraft) async throws -> Bool {
        let result = try await store.saveMeaning(draft)
        if result.inserted { revision += 1 }
        return result.inserted
    }

    func delete(id: Int64) async throws {
        try await store.delete(id: id)
        revision += 1
    }

    func clear() async throws {
        try await store.clear()
        revision += 1
    }

    func setPushed(id: Int64, pushed: Bool) async throws {
        try await store.setPushed(id: id, pushed: pushed)
        revision += 1
    }

    func setMastered(id: Int64, mastered: Bool) async throws {
        try await store.setMastered(id: id, mastered: mastered)
        revision += 1
    }

    func recordPracticeAnswer(id: Int64, correct: Bool) async throws -> SavedWord {
        let word = try await store.recordPracticeAnswer(id: id, correct: correct)
        revision += 1
        return word
    }
}
