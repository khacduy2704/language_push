import XCTest
@testable import PushLanguage

final class WordStoreTests: XCTestCase {
    private func databaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("push_language.db")
    }

    func testSchemaStarterWordsAndReopening() async throws {
        let url = try databaseURL()
        let store = WordStore(databaseURL: url)
        let words = try await store.words()
        XCTAssertEqual(words.map(\.word), [
            "Beautiful", "Example", "Friend", "Happy", "Hello", "Quickly", "Run", "Slowly", "Speak"
        ])
        XCTAssertEqual(words.first(where: { $0.word == "Hello" })?.meaning, "A greeting")
        XCTAssertTrue(words.allSatisfy { !$0.isPushed })
        XCTAssertTrue(words.allSatisfy { $0.practiceScore == 0 && $0.correctAnswers == 0 && $0.incorrectAnswers == 0 })
        let db = try SQLiteConnection(url: url)
        XCTAssertEqual(try db.scalar("PRAGMA user_version"), 6)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM dictionary"), 0)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM cached_audio"), 0)
        let reopened = WordStore(databaseURL: url)
        let reopenedWords = try await reopened.words()
        XCTAssertEqual(words, reopenedWords)
    }

    func testVersionFiveMigratesWithoutLosingWordsMembershipOrOtherTables() async throws {
        let url = try databaseURL()
        let db = try SQLiteConnection(url: url)
        try db.run("""
            CREATE TABLE contacts (
                id INTEGER PRIMARY KEY AUTOINCREMENT, word TEXT NOT NULL,
                partOfSpeech TEXT NOT NULL DEFAULT 'None', meaning TEXT NOT NULL DEFAULT '',
                isPushed INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.run("CREATE TABLE dictionary (id INTEGER PRIMARY KEY, word TEXT)")
        try db.run("CREATE TABLE cached_audio (id INTEGER PRIMARY KEY, word TEXT)")
        try db.run("INSERT INTO contacts (id, word, meaning, isPushed) VALUES (42, 'café 🥝', 'kept', 1)")
        try db.run("INSERT INTO dictionary VALUES (1, 'dictionary kept')")
        try db.run("INSERT INTO cached_audio VALUES (1, 'audio kept')")
        try db.run("PRAGMA user_version = 5")
        let store = WordStore(databaseURL: url)
        let words = try await store.words()
        XCTAssertEqual(words.count, 1)
        let word = try XCTUnwrap(words.first)
        XCTAssertEqual(word.id, 42)
        XCTAssertEqual(word.word, "café 🥝")
        XCTAssertEqual(word.meaning, "kept")
        XCTAssertTrue(word.isPushed)
        XCTAssertFalse(word.isMastered)
        XCTAssertEqual(word.practiceScore, 0)
        XCTAssertEqual(word.correctAnswers, 0)
        XCTAssertEqual(word.incorrectAnswers, 0)
        XCTAssertEqual(try db.scalar("PRAGMA user_version"), 6)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM dictionary"), 1)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM cached_audio"), 1)
        let reopened = try await WordStore(databaseURL: url).words()
        XCTAssertEqual(reopened, words)
    }

    func testFailedMigrationRollsBackAddedColumnsAndPreservesData() async throws {
        let url = try databaseURL()
        let db = try SQLiteConnection(url: url)
        try db.run("CREATE TABLE contacts (id INTEGER, word TEXT, correctAnswers INTEGER)")
        try db.run("INSERT INTO contacts VALUES (42, 'precious', 3)")
        try db.run("PRAGMA user_version = 5")
        do {
            _ = try await WordStore(databaseURL: url).words()
            XCTFail("Conflicting schema must not partially migrate.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("SQLite"))
        }
        XCTAssertEqual(try db.scalar("PRAGMA user_version"), 5)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM contacts"), 1)
        XCTAssertEqual(try db.scalar("SELECT correctAnswers FROM contacts"), 3)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM pragma_table_info('contacts') WHERE name = 'practiceScore'"), 0)
    }

    func testPracticeScoreFloorCountsThresholdAndRelearnPersistIndependently() async throws {
        let url = try databaseURL()
        let store = WordStore(databaseURL: url)
        let first = try await store.add(WordDraft(word: "same", partOfSpeech: "n", meaning: "first"))
        let second = try await store.add(WordDraft(word: "same", partOfSpeech: "n", meaning: "second"))
        try await store.setPushed(id: first.id, pushed: true)
        var updated = try await store.recordPracticeAnswer(id: first.id, correct: false)
        XCTAssertEqual(updated.practiceScore, 0)
        XCTAssertEqual(updated.incorrectAnswers, 1)
        for _ in 0..<3 { updated = try await store.recordPracticeAnswer(id: first.id, correct: true) }
        updated = try await store.recordPracticeAnswer(id: first.id, correct: false)
        XCTAssertEqual(updated.practiceScore, 2)
        XCTAssertEqual(updated.correctAnswers, 3)
        XCTAssertEqual(updated.incorrectAnswers, 2)
        XCTAssertTrue(updated.isPushed)
        for _ in 0..<3 { updated = try await store.recordPracticeAnswer(id: first.id, correct: true) }
        XCTAssertEqual(updated.practiceScore, 5)
        XCTAssertTrue(updated.isMastered)
        XCTAssertFalse(updated.isPushed)
        XCTAssertEqual(updated.correctAnswers, 6)
        let persisted = try await WordStore(databaseURL: url).word(id: first.id)
        XCTAssertEqual(persisted, updated)
        let unaffected = try await store.word(id: second.id)
        XCTAssertEqual(unaffected, second)
        let mastered = try await store.words(query: "same", learningStatus: .mastered)
        let learning = try await store.words(query: "same", learningStatus: .learning)
        XCTAssertEqual(mastered.map(\.id), [first.id])
        XCTAssertEqual(learning.map(\.id), [second.id])
        for correct in [true, false] {
            do {
                _ = try await store.recordPracticeAnswer(id: first.id, correct: correct)
                XCTFail("Stale practice sessions must not mutate a mastered word.")
            } catch WordStorageError.alreadyMastered {}
        }
        do {
            try await store.setPushed(id: first.id, pushed: true)
            XCTFail("Mastered words must not receive reminders.")
        } catch WordStorageError.alreadyMastered {}
        try await store.setMastered(id: first.id, mastered: false)
        updated = try await store.word(id: first.id)
        XCTAssertEqual(updated.practiceScore, 0)
        XCTAssertEqual(updated.correctAnswers, 6)
        XCTAssertEqual(updated.incorrectAnswers, 2)
        XCTAssertFalse(updated.isPushed)
        try await store.setPushed(id: first.id, pushed: true)
        try await store.setMastered(id: first.id, mastered: true)
        updated = try await store.word(id: first.id)
        XCTAssertTrue(updated.isMastered)
        XCTAssertFalse(updated.isPushed)
        XCTAssertEqual(updated.correctAnswers, 6)
        let duplicate = try await store.saveMeaning(WordDraft(word: "same", partOfSpeech: "n", meaning: "first"))
        XCTAssertFalse(duplicate.inserted)
        XCTAssertTrue(duplicate.word.isMastered)
        try await store.update(id: first.id, draft: WordDraft(word: "edited", partOfSpeech: "v", meaning: "edited"))
        let edited = try await store.word(id: first.id)
        XCTAssertTrue(edited.isMastered)
        XCTAssertEqual(edited.correctAnswers, 6)
        try await store.clear()
        let all = try await store.words()
        XCTAssertTrue(all.isEmpty)
    }

    func testScoringFailureAndMissingWordsDoNotApplyPartialChanges() async throws {
        let url = try databaseURL()
        let store = WordStore(databaseURL: url)
        let words = try await store.words()
        let word = try XCTUnwrap(words.first)
        let db = try SQLiteConnection(url: url)
        try db.run("""
            CREATE TRIGGER fail_score BEFORE UPDATE ON contacts
            BEGIN SELECT RAISE(ABORT, 'score write failed'); END
            """)
        do {
            _ = try await store.recordPracticeAnswer(id: word.id, correct: true)
            XCTFail("Write failure must be surfaced.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("score write failed"))
        }
        let unchanged = try await store.word(id: word.id)
        XCTAssertEqual(unchanged, word)
        try db.run("DROP TRIGGER fail_score")
        let retried = try await store.recordPracticeAnswer(id: word.id, correct: true)
        XCTAssertEqual(retried.practiceScore, 1)
        XCTAssertEqual(retried.correctAnswers, 1)
        do {
            _ = try await store.recordPracticeAnswer(id: Int64.max, correct: true)
            XCTFail("Missing word must fail.")
        } catch WordStorageError.missingWord {}
        do {
            try await store.setMastered(id: Int64.max, mastered: true)
            XCTFail("Missing word must fail.")
        } catch WordStorageError.missingWord {}
    }

    func testConcurrentConnectionsOnlyAwardFivePointsAndRemoveMembership() async throws {
        let url = try databaseURL()
        let store = WordStore(databaseURL: url)
        let words = try await store.words()
        let id = try XCTUnwrap(words.first?.id)
        try await store.setPushed(id: id, pushed: true)
        let other = WordStore(databaseURL: url)
        _ = try await other.words()
        let successes = try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<20 {
                let target = index.isMultiple(of: 2) ? store : other
                group.addTask {
                    do {
                        _ = try await target.recordPracticeAnswer(id: id, correct: true)
                        return true
                    } catch WordStorageError.alreadyMastered {
                        return false
                    }
                }
            }
            var count = 0
            for try await success in group { if success { count += 1 } }
            return count
        }
        XCTAssertEqual(successes, 5)
        let mastered = try await store.word(id: id)
        XCTAssertEqual(mastered.practiceScore, 5)
        XCTAssertEqual(mastered.correctAnswers, 5)
        XCTAssertFalse(mastered.isPushed)
    }

    func testCRUDRoundTripsUnicodeQuotesAndEmptyMeaning() async throws {
        let url = try databaseURL()
        let store = WordStore(databaseURL: url)
        let added = try await store.add(WordDraft(
            word: "  O'Brien'); DROP TABLE contacts; --  ", partOfSpeech: " n ",
            meaning: "  quả táo 🥝\nsecond line  "
        ))
        XCTAssertEqual(added.word, "O'Brien'); DROP TABLE contacts; --")
        XCTAssertEqual(added.partOfSpeech, "n")
        XCTAssertEqual(added.meaning, "quả táo 🥝\nsecond line")
        let query = try await store.words(query: "O'Brien")
        XCTAssertEqual(query, [added])
        try await store.update(id: added.id, draft: WordDraft(
            word: " Edited ", partOfSpeech: "", meaning: ""
        ))
        let updated = try await WordStore(databaseURL: url).words(query: "Edited")
        XCTAssertEqual(updated.first?.id, added.id)
        XCTAssertEqual(updated.first?.partOfSpeech, "None")
        XCTAssertEqual(updated.first?.meaning, "")
        try await store.delete(id: added.id)
        let remaining = try await store.words()
        XCTAssertEqual(remaining.count, 9)
        do {
            try await store.delete(id: added.id)
            XCTFail("Missing words must report an error.")
        } catch WordStorageError.missingWord {}
        do {
            try await store.update(id: added.id, draft: WordDraft(word: "gone", partOfSpeech: "n", meaning: ""))
            XCTFail("Updating a missing word must report an error.")
        } catch WordStorageError.missingWord {}
    }

    func testEmptyWordsAreRejectedWithoutChangingData() async throws {
        let store = WordStore(databaseURL: try databaseURL())
        let before = try await store.words()
        do {
            _ = try await store.add(WordDraft(word: " \n", partOfSpeech: "", meaning: ""))
            XCTFail("Blank word must not be silently accepted.")
        } catch WordStorageError.emptyWord {}
        do {
            try await store.update(
                id: try XCTUnwrap(before.first?.id),
                draft: WordDraft(word: "", partOfSpeech: "", meaning: "")
            )
            XCTFail("Invalid edits must not overwrite data.")
        } catch WordStorageError.emptyWord {}
        let after = try await store.words()
        XCTAssertEqual(before, after)
    }

    func testBoundTextPreservesEmbeddedNULBytes() async throws {
        let store = WordStore(databaseURL: try databaseURL())
        let draft = WordDraft(word: "word\u{0}suffix", partOfSpeech: "n", meaning: "first\u{0}second")
        let added = try await store.add(draft)
        let rows = try await store.words()
        XCTAssertEqual(rows.first(where: { $0.id == added.id })?.word, draft.word)
        XCTAssertEqual(rows.first(where: { $0.id == added.id })?.meaning, draft.meaning)
    }

    func testDictionaryMeaningDeduplicationButManualDuplicatesAllowed() async throws {
        let store = WordStore(databaseURL: try databaseURL())
        let first = try await store.saveMeaning(WordDraft(word: " apple ", partOfSpeech: "danh từ", meaning: " quả táo "))
        let duplicate = try await store.saveMeaning(WordDraft(word: "APPLE", partOfSpeech: "n", meaning: "quả táo"))
        XCTAssertTrue(first.inserted)
        XCTAssertFalse(duplicate.inserted)
        XCTAssertEqual(first.word.id, duplicate.word.id)
        let second = try await store.saveMeaning(WordDraft(word: "apple", partOfSpeech: "n", meaning: "another meaning"))
        XCTAssertTrue(second.inserted)
        _ = try await store.add(WordDraft(word: "apple", partOfSpeech: "n", meaning: "quả táo"))
        let results = try await store.words(query: "apple")
        XCTAssertEqual(results.count, 3)
    }

    func testConcurrentMeaningSavesCreateOnlyOneRecord() async throws {
        let store = WordStore(databaseURL: try databaseURL())
        let inserted = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await store.saveMeaning(WordDraft(word: "apple", partOfSpeech: "n", meaning: "fruit")).inserted
                }
            }
            var count = 0
            for try await result in group {
                if result { count += 1 }
            }
            return count
        }
        XCTAssertEqual(inserted, 1)
        let results = try await store.words(query: "apple")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchRanksLikeFlutterAndPreservesPushedFlagDuringEdits() async throws {
        let url = try databaseURL()
        let store = WordStore(databaseURL: url)
        for word in ["pineapple", "Applesauce", "APPLE"] {
            _ = try await store.add(WordDraft(word: word, partOfSpeech: "n", meaning: "fruit"))
        }
        let results = try await store.words(query: " apple ")
        XCTAssertEqual(results.map(\.word), ["APPLE", "Applesauce", "pineapple"])
        let pushed = try XCTUnwrap(results.first)
        let db = try SQLiteConnection(url: url)
        try db.run("UPDATE contacts SET isPushed = 1 WHERE id = ?", values: [.integer(pushed.id)])
        let filtered = try await store.words(query: "apple", includePushed: false)
        XCTAssertEqual(filtered.map(\.word), ["Applesauce", "pineapple"])
        try await store.update(id: pushed.id, draft: WordDraft(word: "apple", partOfSpeech: "v", meaning: "edited"))
        let updated = try await store.words(query: "apple")
        XCTAssertEqual(updated.first?.isPushed, true)
        let wildcard = try await store.words(query: "%")
        let all = try await store.words()
        XCTAssertEqual(wildcard.count, all.count)
    }

    func testClearPersistsWithoutReseedingAndDoesNotDeleteOtherTables() async throws {
        let url = try databaseURL()
        let store = WordStore(databaseURL: url)
        _ = try await store.words()
        let db = try SQLiteConnection(url: url)
        try db.run("INSERT INTO dictionary (word) VALUES ('kept')")
        try db.run("INSERT INTO cached_audio (word, filePath, downloadedAt) VALUES ('kept', '/audio', 'date')")
        try await store.clear()
        let reopenedWords = try await WordStore(databaseURL: url).words()
        XCTAssertEqual(reopenedWords, [])
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM dictionary"), 1)
        XCTAssertEqual(try db.scalar("SELECT count(*) FROM cached_audio"), 1)
        let added = try await store.add(WordDraft(word: "new", partOfSpeech: "", meaning: ""))
        XCTAssertGreaterThan(added.id, 9)
    }

    func testUnsupportedUnversionedAndCorruptDatabasesAreNeverReset() async throws {
        for version in [0, 1, 7] {
            let url = try databaseURL()
            let db = try SQLiteConnection(url: url)
            try db.run("CREATE TABLE precious (value TEXT)")
            try db.run("INSERT INTO precious VALUES ('keep me')")
            try db.run("PRAGMA user_version = \(version)")
            let store = WordStore(databaseURL: url)
            do {
                _ = try await store.words()
                XCTFail("Unsupported schema must not be overwritten.")
            } catch WordStorageError.unsupportedVersion(let found) {
                XCTAssertEqual(found, Int64(version))
            }
            XCTAssertEqual(try db.scalar("SELECT count(*) FROM precious"), 1)
        }
        let url = try databaseURL()
        let original = Data("not a sqlite database".utf8)
        try original.write(to: url)
        do {
            _ = try await WordStore(databaseURL: url).words()
            XCTFail("Corrupt database must be reported, not replaced.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("SQLite"))
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDatabaseOpenCanRetryWithoutDeletingData() async throws {
        let url = try databaseURL()
        let blockedURL = url.appendingPathComponent("blocked.db")
        let store = WordStore(databaseURL: blockedURL)
        do {
            _ = try await store.words()
            XCTFail("Missing parent directory must report a failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("SQLite"))
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let words = try await store.words()
        XCTAssertEqual(words.count, 9)
    }

    func testDefinitionMeaningUsesItsOwnPartOfSpeech() {
        let lines = DefinitionLine.parse("* noun\n- fruit\n* verb\n- act\nplain continuation")
        XCTAssertEqual(lines.map(\.partOfSpeech), ["noun", "noun", "verb", "verb", "verb"])
        XCTAssertEqual(DefinitionLine.parse("- unsectioned").first?.partOfSpeech, "None")
    }

    @MainActor
    func testLibraryPublishesRevisionOnlyAfterSuccessfulMutations() async throws {
        let library = WordLibrary(store: WordStore(databaseURL: try databaseURL()))
        try await library.save(WordDraft(word: "test", partOfSpeech: "", meaning: "test"))
        XCTAssertEqual(library.revision, 1)
        let inserted = try await library.saveMeaning(WordDraft(word: "test", partOfSpeech: "", meaning: "test"))
        XCTAssertFalse(inserted)
        XCTAssertEqual(library.revision, 1)
        do {
            try await library.save(WordDraft(word: "", partOfSpeech: "", meaning: ""))
            XCTFail("Invalid mutation must fail.")
        } catch WordStorageError.emptyWord {}
        XCTAssertEqual(library.revision, 1)
        try await library.clear()
        XCTAssertEqual(library.revision, 2)
    }
}
