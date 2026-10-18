import Foundation
import Combine

enum PracticeMode: CaseIterable, Hashable {
    case typing
    case flashcard
}

struct PracticeTurn {
    let word: SavedWord
    let mode: PracticeMode
}

enum PracticeError: LocalizedError {
    case emptyWords
    case invalidWords
    case noActiveQuestion
    case emptyAnswer
    case alreadyChecked
    case invalidOption
    case uncheckedAnswer
    case savingAnswer

    var errorDescription: String? {
        switch self {
        case .emptyWords: return AppLocalization.text("No words in push list to practice.")
        case .invalidWords: return AppLocalization.text("Practice requires distinct saved words with nonempty headwords.")
        case .noActiveQuestion: return AppLocalization.text("This practice session has finished.")
        case .emptyAnswer: return AppLocalization.text("Type an answer before checking.")
        case .alreadyChecked: return AppLocalization.text("This answer has already been checked.")
        case .invalidOption: return AppLocalization.text("Choose one of the current flashcard options.")
        case .uncheckedAnswer: return AppLocalization.text("Check the answer before continuing.")
        case .savingAnswer: return AppLocalization.text("Please wait while your practice result is saved.")
        }
    }
}

@MainActor
final class PracticeSession: ObservableObject {
    let words: [SavedWord]
    let turns: [PracticeTurn]
    @Published private(set) var index = 0
    @Published private(set) var answer = ""
    @Published private(set) var result: Bool?
    @Published private(set) var options: [String] = []
    @Published private(set) var selectedOption: Int?
    @Published private(set) var finished = false
    @Published private(set) var completedIDs: Set<Int64> = []
    @Published private(set) var recording = false
    @Published private(set) var recordedWord: SavedWord?
    private let shuffle: ([String]) -> [String]

    convenience init(words: [SavedWord]) throws {
        try self.init(
            words: words, modes: { PracticeMode.allCases.shuffled() },
            shuffle: { $0.shuffled() }
        )
    }

    init(
        words: [SavedWord], modes: () -> [PracticeMode],
        shuffle: @escaping ([String]) -> [String]
    ) throws {
        guard !words.isEmpty else { throw PracticeError.emptyWords }
        guard Set(words.map(\.id)).count == words.count,
              words.allSatisfy({ !Self.normalized($0.word).isEmpty && !$0.isMastered }) else {
            throw PracticeError.invalidWords
        }
        self.words = words
        self.shuffle = shuffle
        var turns: [PracticeTurn] = []
        for word in words {
            let order = modes()
            guard order.count == 2, Set(order) == Set(PracticeMode.allCases) else {
                throw PracticeError.invalidWords
            }
            turns += order.map { PracticeTurn(word: word, mode: $0) }
        }
        self.turns = turns
        prepareOptions()
    }

    var current: PracticeTurn? { finished ? nil : turns[index] }
    var hasNext: Bool { nextIndex != nil }
    var canCheck: Bool { !recording && !finished && result == nil && !Self.normalized(answer).isEmpty }

    private var nextIndex: Int? {
        turns.indices.first { $0 > index && !completedIDs.contains(turns[$0].word.id) }
    }

    func setAnswer(_ value: String) {
        guard !recording, result == nil, let current else { return }
        let cleaned = value.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        answer = String(cleaned.prefix(current.word.word.count))
    }

    @discardableResult
    func check(option: Int? = nil) throws -> Bool {
        let correct = try evaluate(option: option)
        accept(correct: correct, option: option)
        return correct
    }

    @discardableResult
    func check(
        option: Int? = nil,
        record: (Int64, Bool) async throws -> SavedWord
    ) async throws -> Bool {
        let correct = try evaluate(option: option)
        guard let current else { throw PracticeError.noActiveQuestion }
        recording = true
        defer { recording = false }
        recordedWord = try await record(current.word.id, correct)
        accept(correct: correct, option: option)
        return correct
    }

    private func evaluate(option: Int?) throws -> Bool {
        guard !recording else { throw PracticeError.savingAnswer }
        guard let current else { throw PracticeError.noActiveQuestion }
        guard result == nil else { throw PracticeError.alreadyChecked }
        let submitted: String
        if current.mode == .flashcard {
            guard let option, options.indices.contains(option) else { throw PracticeError.invalidOption }
            submitted = options[option]
        } else {
            guard canCheck else { throw PracticeError.emptyAnswer }
            submitted = answer
        }
        return Self.normalized(submitted) == Self.normalized(current.word.word)
    }

    private func accept(correct: Bool, option: Int?) {
        guard let current else { return }
        if current.mode == .flashcard { selectedOption = option }
        if correct { completedIDs.insert(current.word.id) }
        result = correct
    }

    func advance() throws {
        guard !recording else { throw PracticeError.savingAnswer }
        guard !finished else { throw PracticeError.noActiveQuestion }
        guard result != nil else { throw PracticeError.uncheckedAnswer }
        guard let nextIndex else {
            finished = true
            return
        }
        index = nextIndex
        answer = ""
        result = nil
        selectedOption = nil
        recordedWord = nil
        prepareOptions()
    }

    private func prepareOptions() {
        let correct = turns[index].word.word
        var seen: Set<String> = []
        let pool = words.map(\.word).filter {
            Self.normalized($0) != Self.normalized(correct) && seen.insert($0).inserted
        }
        var options = [correct] + shuffle(pool).prefix(3)
        while options.count < 4 { options.append(correct) }
        self.options = shuffle(options)
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
