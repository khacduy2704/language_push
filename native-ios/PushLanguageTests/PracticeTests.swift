import AVFoundation
import XCTest
@testable import PushLanguage

@MainActor
final class PracticeTests: XCTestCase {
    private func word(_ id: Int64, _ text: String = "Hello", meaning: String = "A greeting") -> SavedWord {
        SavedWord(id: id, word: text, partOfSpeech: "n", meaning: meaning, isPushed: true)
    }

    private func session(_ words: [SavedWord], flashFirst: Bool = false) throws -> PracticeSession {
        try PracticeSession(
            words: words, modes: { flashFirst ? [.flashcard, .typing] : [.typing, .flashcard] },
            shuffle: { $0 }
        )
    }

    func testOneCorrectAnswerSkipsRemainingWordTurnsAndFinishes() throws {
        let practice = try session([word(1), word(2, "Run", meaning: "Move")])
        XCTAssertEqual(practice.turns.count, 4)
        XCTAssertEqual(practice.current?.mode, .typing)
        practice.setAnswer("hello")
        XCTAssertTrue(try practice.check())
        XCTAssertEqual(practice.completedIDs, [1])
        XCTAssertTrue(practice.hasNext)
        try practice.advance()
        XCTAssertEqual(practice.index, 2)
        XCTAssertEqual(practice.current?.word.word, "Run")
        XCTAssertEqual(practice.answer, "")
        XCTAssertNil(practice.result)
        practice.setAnswer("RUN")
        XCTAssertTrue(try practice.check())
        XCTAssertFalse(practice.hasNext)
        try practice.advance()
        XCTAssertTrue(practice.finished)
        XCTAssertNil(practice.current)
        XCTAssertThrowsError(try practice.check())
        XCTAssertThrowsError(try practice.advance())
    }

    func testWrongAnswerLeavesLaterModeAvailableButNoInfiniteRetry() throws {
        let practice = try session([word(1), word(2, "Run")])
        practice.setAnswer("wrong")
        XCTAssertFalse(try practice.check())
        XCTAssertTrue(practice.completedIDs.isEmpty)
        try practice.advance()
        XCTAssertEqual(practice.current?.mode, .flashcard)
        let wrong = try XCTUnwrap(practice.options.firstIndex(of: "Run"))
        XCTAssertFalse(try practice.check(option: wrong))
        try practice.advance()
        XCTAssertEqual(practice.index, 2)
        practice.setAnswer("Run")
        XCTAssertTrue(try practice.check())
        try practice.advance()
        XCTAssertTrue(practice.finished)
        XCTAssertEqual(practice.completedIDs, [2])
    }

    func testFourFlashcardsIncludeCorrectWithSmallPoolsAndDuplicateHeadwords() throws {
        for words in [
            [word(1)],
            [word(1), word(2, "hello", meaning: "Another meaning")],
            [word(1), word(2, "Run"), word(3, "Friend"), word(4, "Happy"), word(5, "Speak")]
        ] {
            let practice = try session(words, flashFirst: true)
            XCTAssertEqual(practice.options.count, 4)
            XCTAssertTrue(practice.options.contains("Hello"))
            XCTAssertFalse(practice.options.contains("hello"))
            XCTAssertTrue(try practice.check(option: 0))
            XCTAssertThrowsError(try practice.check(option: 0))
            XCTAssertEqual(practice.completedIDs, [1])
        }
        let duplicates = try session([word(1), word(2, "Hello", meaning: "Other")])
        duplicates.setAnswer("hello")
        _ = try duplicates.check()
        try duplicates.advance()
        XCTAssertEqual(duplicates.current?.word.id, 2)
    }

    func testInputNormalizationLengthUnicodeAndAnswerLocking() throws {
        let practice = try session([word(1, "New York")])
        practice.setAnswer("New\n   YorkEXTRA")
        XCTAssertEqual(practice.answer, "New York")
        XCTAssertTrue(try practice.check())
        practice.setAnswer("different")
        XCTAssertEqual(practice.answer, "New York")
        XCTAssertThrowsError(try practice.check())
        let unicode = try session([word(2, "café 🥝")])
        unicode.setAnswer("CAFÉ 🥝extra")
        XCTAssertEqual(unicode.answer, "CAFÉ 🥝")
        XCTAssertTrue(try unicode.check())
    }

    func testEmptyInputInvalidOptionsAndUncheckedAdvanceDoNotMutate() throws {
        let practice = try session([word(1)])
        XCTAssertFalse(practice.canCheck)
        XCTAssertThrowsError(try practice.check())
        practice.setAnswer(" ")
        XCTAssertFalse(practice.canCheck)
        XCTAssertThrowsError(try practice.advance())
        XCTAssertEqual(practice.index, 0)
        XCTAssertNil(practice.result)
        let flash = try session([word(1)], flashFirst: true)
        XCTAssertThrowsError(try flash.check())
        XCTAssertThrowsError(try flash.check(option: -1))
        XCTAssertThrowsError(try flash.check(option: 4))
        XCTAssertNil(flash.selectedOption)
        XCTAssertNil(flash.result)
    }

    func testEmptyAndInvalidSessionsFailExplicitly() {
        XCTAssertThrowsError(try session([]))
        XCTAssertThrowsError(try session([word(1, " \n")]))
        XCTAssertThrowsError(try session([word(1), word(1)]))
        XCTAssertThrowsError(try PracticeSession(words: [word(1)], modes: { [.typing] }, shuffle: { $0 }))
    }

    func testLargePushListCanCompletePracticeWithoutFiveWordLimit() throws {
        let words = (1...30).map { word(Int64($0), "Word \($0)") }
        let practice = try session(words)
        XCTAssertEqual(practice.turns.count, 60)
        for word in words {
            XCTAssertEqual(practice.current?.word.id, word.id)
            practice.setAnswer(word.word)
            XCTAssertTrue(try practice.check())
            try practice.advance()
        }
        XCTAssertTrue(practice.finished)
        XCTAssertEqual(practice.completedIDs.count, words.count)
    }

    func testSessionSnapshotDoesNotDependOnLaterMembershipChanges() throws {
        var words = [word(1)]
        let practice = try session(words)
        words.removeAll()
        XCTAssertEqual(practice.words.count, 1)
        XCTAssertEqual(practice.current?.word.word, "Hello")
    }

    func testProductionSessionsShuffleBothModesForEachWord() throws {
        for _ in 0..<20 {
            let practice = try PracticeSession(words: [word(1), word(2, "Run")])
            XCTAssertEqual(practice.turns.count, 4)
            for id in [Int64(1), 2] {
                XCTAssertEqual(Set(practice.turns.filter { $0.word.id == id }.map(\.mode)), Set(PracticeMode.allCases))
            }
            XCTAssertEqual(practice.options.count, 4)
        }
    }

    func testRecordedAnswersPersistBeforeFeedbackAndRetryDoesNotDoubleScore() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).db")
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let library = WordLibrary(store: WordStore(databaseURL: url))
        let words = try await library.store.words()
        let word = try XCTUnwrap(words.first)
        try await library.setPushed(id: word.id, pushed: true)
        let practice = try session([word])
        practice.setAnswer(word.word)
        do {
            _ = try await practice.check { _, _ in
                throw WordStorageError.sqlite("Test failure")
            }
            XCTFail("Recording must fail explicitly.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Test failure"))
        }
        XCTAssertNil(practice.result)
        XCTAssertFalse(practice.recording)
        XCTAssertTrue(practice.completedIDs.isEmpty)
        XCTAssertNil(practice.recordedWord)
        let revision = library.revision
        let correct = try await practice.check { id, correct in
            try await library.recordPracticeAnswer(id: id, correct: correct)
        }
        XCTAssertTrue(correct)
        XCTAssertEqual(practice.result, true)
        XCTAssertEqual(practice.recordedWord?.practiceScore, 1)
        XCTAssertEqual(practice.recordedWord?.correctAnswers, 1)
        XCTAssertEqual(library.revision, revision + 1)
        do {
            _ = try await practice.check { id, correct in
                try await library.recordPracticeAnswer(id: id, correct: correct)
            }
            XCTFail("One checked answer must not be recorded twice.")
        } catch PracticeError.alreadyChecked {}
        XCTAssertEqual(library.revision, revision + 1)
    }

    func testBusyAnswerCannotChangeAdvanceOrSubmitAgain() async throws {
        let practice = try session([word(1)])
        practice.setAnswer("hello")
        var continuation: CheckedContinuation<Void, Never>?
        var calls = 0
        let checking = Task {
            try await practice.check { id, _ in
                calls += 1
                await withCheckedContinuation { continuation = $0 }
                return SavedWord(id: id, word: "Hello", partOfSpeech: "n", meaning: "", isPushed: true, practiceScore: 1)
            }
        }
        while continuation == nil { await Task.yield() }
        XCTAssertTrue(practice.recording)
        XCTAssertFalse(practice.canCheck)
        practice.setAnswer("different")
        XCTAssertEqual(practice.answer, "hello")
        XCTAssertThrowsError(try practice.advance())
        do {
            _ = try await practice.check { _, _ in
                XCTFail("Duplicate operation must not reach persistence.")
                return self.word(1)
            }
            XCTFail("Busy operation must be rejected.")
        } catch PracticeError.savingAnswer {}
        continuation?.resume()
        let correct = try await checking.value
        XCTAssertTrue(correct)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(practice.recording)
        XCTAssertEqual(practice.result, true)
    }

    func testWrongAnswersReducePointsAndFifthCorrectAnswerMastersAcrossSessions() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).db")
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let library = WordLibrary(store: WordStore(databaseURL: url))
        let rows = try await library.store.words()
        let original = try XCTUnwrap(rows.first)
        try await library.setPushed(id: original.id, pushed: true)
        for correct in [false, true, false, true, true, true, true, true] {
            let word = try await library.store.word(id: original.id)
            let practice = try session([word])
            practice.setAnswer(correct ? word.word : "zz")
            let result = try await practice.check { id, correct in
                try await library.recordPracticeAnswer(id: id, correct: correct)
            }
            XCTAssertEqual(result, correct)
            if correct { try practice.advance(); XCTAssertTrue(practice.finished) }
        }
        let final = try await WordStore(databaseURL: url).word(id: original.id)
        XCTAssertTrue(final.isMastered)
        XCTAssertEqual(final.practiceScore, 5)
        XCTAssertEqual(final.correctAnswers, 6)
        XCTAssertEqual(final.incorrectAnswers, 2)
        XCTAssertFalse(final.isPushed)
        XCTAssertThrowsError(try session([final]))
    }

    func testBundledFeedbackSoundsDecodeAndPlaybackCanBeReplacedAndStopped() throws {
        for name in ["correct", "incorrect"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "mp3"))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0)
        }
        let feedback = PracticeFeedback()
        feedback.play(correct: true)
        XCTAssertNil(feedback.errorMessage)
        feedback.play(correct: false)
        XCTAssertNil(feedback.errorMessage)
        feedback.stop()
        XCTAssertNil(feedback.errorMessage)
    }
}
