import Foundation
import SQLite3

actor WordStore {
    private let databaseURL: URL?
    private var connection: SQLiteConnection?

    init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
    }

    private func database() throws -> SQLiteConnection {
        if let connection { return connection }
        let url = try location()
        let db = try SQLiteConnection(url: url)
        let version = try db.scalar("PRAGMA user_version")
        if version == 0 {
            // Only initialize an empty database; never overwrite unversioned user data.
            guard try db.scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table'") == 0 else {
                throw WordStorageError.unsupportedVersion(version)
            }
            try db.run("BEGIN IMMEDIATE")
            do {
                try db.run("""
                    CREATE TABLE contacts (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        word TEXT NOT NULL,
                        partOfSpeech TEXT NOT NULL DEFAULT 'None',
                        meaning TEXT NOT NULL DEFAULT '',
                        isPushed INTEGER NOT NULL DEFAULT 0,
                        practiceScore INTEGER NOT NULL DEFAULT 0 CHECK (practiceScore BETWEEN 0 AND 5),
                        correctAnswers INTEGER NOT NULL DEFAULT 0 CHECK (correctAnswers >= 0),
                        incorrectAnswers INTEGER NOT NULL DEFAULT 0 CHECK (incorrectAnswers >= 0)
                    )
                    """)
                try db.run("""
                    CREATE TABLE dictionary (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        word TEXT NOT NULL UNIQUE,
                        ipa TEXT NOT NULL DEFAULT '',
                        partOfSpeech TEXT NOT NULL DEFAULT '',
                        meaning TEXT NOT NULL DEFAULT ''
                    )
                    """)
                try db.run("""
                    CREATE TABLE cached_audio (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        word TEXT NOT NULL UNIQUE,
                        filePath TEXT NOT NULL,
                        downloadedAt TEXT NOT NULL
                    )
                    """)
                for draft in Self.starterWords {
                    try Self.insert(draft, into: db)
                }
                try db.run("PRAGMA user_version = 6")
                try db.run("COMMIT")
            } catch {
                let initializationError = error
                do {
                    try db.run("ROLLBACK")
                } catch {
                    throw WordStorageError.sqlite(
                        "\(initializationError.localizedDescription) Rollback failed: \(error.localizedDescription)"
                    )
                }
                throw initializationError
            }
        } else if version == 5 {
            try db.run("BEGIN IMMEDIATE")
            do {
                if try db.scalar("PRAGMA user_version") == 5 {
                    try db.run("ALTER TABLE contacts ADD COLUMN practiceScore INTEGER NOT NULL DEFAULT 0 CHECK (practiceScore BETWEEN 0 AND 5)")
                    try db.run("ALTER TABLE contacts ADD COLUMN correctAnswers INTEGER NOT NULL DEFAULT 0 CHECK (correctAnswers >= 0)")
                    try db.run("ALTER TABLE contacts ADD COLUMN incorrectAnswers INTEGER NOT NULL DEFAULT 0 CHECK (incorrectAnswers >= 0)")
                    try db.run("PRAGMA user_version = 6")
                }
                try db.run("COMMIT")
            } catch {
                let migrationError = error
                do {
                    try db.run("ROLLBACK")
                } catch {
                    throw WordStorageError.sqlite(
                        "\(migrationError.localizedDescription) Rollback failed: \(error.localizedDescription)"
                    )
                }
                throw migrationError
            }
        } else if version != 6 {
            throw WordStorageError.unsupportedVersion(version)
        }
        try db.run("SELECT \(Self.wordColumns) FROM contacts LIMIT 0")
        connection = db
        return db
    }

    func location() throws -> URL {
        let url: URL
        if let databaseURL {
            url = databaseURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let directory = support.appendingPathComponent("PushLanguage", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("push_language.db")
        }
        return url
    }

    private static let wordColumns = "id, word, partOfSpeech, meaning, isPushed, practiceScore, correctAnswers, incorrectAnswers"

    func words(
        query: String = "", includePushed: Bool = true, learningStatus: WordLearningStatus? = nil
    ) throws -> [SavedWord] {
        let db = try database()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var words: [SavedWord] = []
        let status: Int64 = learningStatus.map { $0 == .mastered ? 1 : 0 } ?? -1
        if query.isEmpty {
            try db.run("""
                SELECT \(Self.wordColumns) FROM contacts
                WHERE (? = 1 OR isPushed = 0) AND (? = -1 OR (practiceScore = 5) = ?)
                ORDER BY word COLLATE NOCASE ASC
                """, values: [.integer(includePushed ? 1 : 0), .integer(status), .integer(status)]) {
                words.append(try Self.word(from: $0))
            }
        } else {
            try db.run("""
                SELECT \(Self.wordColumns) FROM contacts
                WHERE word LIKE ? AND (? = 1 OR isPushed = 0) AND (? = -1 OR (practiceScore = 5) = ?)
                ORDER BY CASE WHEN lower(word) = lower(?) THEN 0
                    WHEN lower(word) LIKE lower(?) THEN 1 ELSE 2 END,
                    word COLLATE NOCASE ASC
                """, values: [
                    .text("%\(query)%"), .integer(includePushed ? 1 : 0),
                    .integer(status), .integer(status),
                    .text(query), .text("\(query)%")
                ]) { words.append(try Self.word(from: $0)) }
        }
        return words
    }

    func add(_ draft: WordDraft) throws -> SavedWord {
        let draft = try draft.validated()
        let db = try database()
        try Self.insert(draft, into: db)
        return SavedWord(
            id: db.insertedID, word: draft.word, partOfSpeech: draft.partOfSpeech,
            meaning: draft.meaning, isPushed: false
        )
    }

    func saveMeaning(_ draft: WordDraft) throws -> (word: SavedWord, inserted: Bool) {
        let draft = try draft.validated()
        let db = try database()
        var existing: SavedWord?
        try db.run("""
            SELECT \(Self.wordColumns) FROM contacts
            WHERE lower(word) = lower(?) AND meaning = ? LIMIT 1
            """, values: [.text(draft.word), .text(draft.meaning)]) {
                existing = try Self.word(from: $0)
            }
        if let existing { return (existing, false) }
        return (try add(draft), true)
    }

    func update(id: Int64, draft: WordDraft) throws {
        let draft = try draft.validated()
        let db = try database()
        try db.run("""
            UPDATE contacts SET word = ?, partOfSpeech = ?, meaning = ? WHERE id = ?
            """, values: [.text(draft.word), .text(draft.partOfSpeech), .text(draft.meaning), .integer(id)])
        guard db.changes == 1 else { throw WordStorageError.missingWord }
    }

    func delete(id: Int64) throws {
        let db = try database()
        try db.run("DELETE FROM contacts WHERE id = ?", values: [.integer(id)])
        guard db.changes == 1 else { throw WordStorageError.missingWord }
    }

    func clear() throws {
        try database().run("DELETE FROM contacts")
    }

    func setPushed(id: Int64, pushed: Bool) throws {
        let db = try database()
        try db.run("""
            UPDATE contacts SET isPushed = ? WHERE id = ? AND (? = 0 OR practiceScore < 5)
            """, values: [.integer(pushed ? 1 : 0), .integer(id), .integer(pushed ? 1 : 0)])
        if db.changes == 0 {
            if try word(id: id).isMastered { throw WordStorageError.alreadyMastered }
            throw WordStorageError.missingWord
        }
    }

    func word(id: Int64) throws -> SavedWord {
        var found: SavedWord?
        try database().run("SELECT \(Self.wordColumns) FROM contacts WHERE id = ?", values: [.integer(id)]) {
            found = try Self.word(from: $0)
        }
        guard let found else { throw WordStorageError.missingWord }
        return found
    }

    func setMastered(id: Int64, mastered: Bool) throws {
        let db = try database()
        try db.run("""
            UPDATE contacts SET practiceScore = ?, isPushed = 0 WHERE id = ?
            """, values: [.integer(mastered ? 5 : 0), .integer(id)])
        guard db.changes == 1 else { throw WordStorageError.missingWord }
    }

    func recordPracticeAnswer(id: Int64, correct: Bool) throws -> SavedWord {
        let db = try database()
        try db.run("BEGIN IMMEDIATE")
        do {
            try db.run("""
                UPDATE contacts SET
                    practiceScore = min(5, max(0, practiceScore + ?)),
                    correctAnswers = correctAnswers + ?,
                    incorrectAnswers = incorrectAnswers + ?,
                    isPushed = CASE WHEN practiceScore + ? >= 5 THEN 0 ELSE isPushed END
                WHERE id = ? AND practiceScore < 5
                """, values: [
                    .integer(correct ? 1 : -1), .integer(correct ? 1 : 0),
                    .integer(correct ? 0 : 1), .integer(correct ? 1 : -1), .integer(id)
                ])
            guard db.changes == 1 else {
                if try word(id: id).isMastered { throw WordStorageError.alreadyMastered }
                throw WordStorageError.missingWord
            }
            let updated = try word(id: id)
            try db.run("COMMIT")
            return updated
        } catch {
            let recordingError = error
            do {
                try db.run("ROLLBACK")
            } catch {
                throw WordStorageError.sqlite(
                    "\(recordingError.localizedDescription) Rollback failed: \(error.localizedDescription)"
                )
            }
            throw recordingError
        }
    }

    private static func insert(_ draft: WordDraft, into db: SQLiteConnection) throws {
        try db.run(
            "INSERT INTO contacts (word, partOfSpeech, meaning, isPushed) VALUES (?, ?, ?, 0)",
            values: [.text(draft.word), .text(draft.partOfSpeech), .text(draft.meaning)]
        )
    }

    private static func word(from row: OpaquePointer) throws -> SavedWord {
        guard sqlite3_column_type(row, 0) == SQLITE_INTEGER,
              (4...7).allSatisfy({ sqlite3_column_type(row, Int32($0)) == SQLITE_INTEGER }),
              (0...5).contains(sqlite3_column_int64(row, 5)),
              sqlite3_column_int64(row, 6) >= 0, sqlite3_column_int64(row, 7) >= 0 else {
            throw WordStorageError.invalidRow
        }
        return SavedWord(
            id: sqlite3_column_int64(row, 0), word: try SQLiteConnection.text(row, column: 1),
            partOfSpeech: try SQLiteConnection.text(row, column: 2),
            meaning: try SQLiteConnection.text(row, column: 3),
            isPushed: sqlite3_column_int64(row, 4) != 0,
            practiceScore: Int(sqlite3_column_int64(row, 5)),
            correctAnswers: Int(sqlite3_column_int64(row, 6)),
            incorrectAnswers: Int(sqlite3_column_int64(row, 7))
        )
    }

    private static let starterWords = [
        WordDraft(word: "Hello", partOfSpeech: "n", meaning: "A greeting"),
        WordDraft(word: "Run", partOfSpeech: "v", meaning: "To move quickly"),
        WordDraft(word: "Beautiful", partOfSpeech: "adj", meaning: "Pleasing to the eye"),
        WordDraft(word: "Quickly", partOfSpeech: "adv", meaning: "In a fast manner"),
        WordDraft(word: "Example", partOfSpeech: "n", meaning: "A thing characteristic of its kind"),
        WordDraft(word: "Speak", partOfSpeech: "v", meaning: "To say something"),
        WordDraft(word: "Happy", partOfSpeech: "adj", meaning: "Feeling pleasure"),
        WordDraft(word: "Slowly", partOfSpeech: "adv", meaning: "In a slow manner"),
        WordDraft(word: "Friend", partOfSpeech: "n", meaning: "A person with whom one has a bond")
    ]
}
