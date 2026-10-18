import Foundation

struct DictionaryEntry: Identifiable, Equatable, Sendable {
    let word: String
    let ipa: String
    let preview: String
    let partOfSpeech: String
    let offset: Int
    let length: Int
    let score: Int

    var id: Int { offset }
}

enum DictionaryError: LocalizedError {
    case missingResource
    case noEntries
    case invalidLimit
    case invalidEntry

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return AppLocalization.text("The offline dictionary resource is missing from this app.")
        case .noEntries:
            return AppLocalization.text("The dictionary contains no readable word entries.")
        case .invalidLimit:
            return AppLocalization.text("The search result limit must be greater than zero.")
        case .invalidEntry:
            return AppLocalization.text("This word's definition could not be read from the dictionary.")
        }
    }
}
