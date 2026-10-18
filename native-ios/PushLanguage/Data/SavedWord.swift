import Foundation

enum WordLearningStatus: String, CaseIterable, Identifiable {
    case learning = "To Learn"
    case mastered = "Mastered"

    var id: String { rawValue }
}

struct SavedWord: Identifiable, Equatable, Sendable {
    let id: Int64
    let word: String
    let partOfSpeech: String
    let meaning: String
    let isPushed: Bool
    var practiceScore: Int = 0
    var correctAnswers: Int = 0
    var incorrectAnswers: Int = 0

    var isMastered: Bool { practiceScore == 5 }
}

struct WordDraft: Sendable {
    let word: String
    let partOfSpeech: String
    let meaning: String

    func validated() throws -> WordDraft {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let pos = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { throw WordStorageError.emptyWord }
        return WordDraft(
            word: word, partOfSpeech: pos.isEmpty ? "None" : pos,
            meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

enum WordStorageError: LocalizedError {
    case emptyWord
    case missingWord
    case unsupportedVersion(Int64)
    case sqlite(String)
    case invalidRow
    case alreadyMastered

    var errorDescription: String? {
        switch self {
        case .emptyWord: return AppLocalization.text("Enter a word before saving.")
        case .missingWord: return AppLocalization.text("This saved word no longer exists. Refresh the list.")
        case .unsupportedVersion(let version):
            return AppLocalization.format("Database version %lld is not supported. Your database has not been reset.", version)
        case .sqlite(let message): return "SQLite: \(message)"
        case .invalidRow: return AppLocalization.text("A saved word contains invalid data. Your database has not been reset.")
        case .alreadyMastered: return AppLocalization.text("This word is already mastered. Choose Learn Again before adding it to reminders or practicing.")
        }
    }
}
