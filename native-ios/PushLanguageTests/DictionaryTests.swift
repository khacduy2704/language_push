import XCTest
@testable import PushLanguage

final class DictionaryTests: XCTestCase {
    private let fixture = """
    \u{FEFF}@Apple /apple/
    * noun
    - quả táo
    =an apple+ một quả táo
    !idiom
    * second section
    - another meaning
    @apple /duplicate/
    * noun
    - duplicate
    @applesauce
    - sauce
    @pineapple
    - fruit
    @map
    - map meaning
    @last
    plain content without a section
    """

    func testSearchRankingDuplicatesAndLimits() throws {
        let index = try DictionaryIndex(data: Data(fixture.utf8))
        let results = try index.search(query: "  APPLE\n", limit: 50)
        XCTAssertEqual(results.map(\.word), ["Apple", "apple", "applesauce", "pineapple"])
        XCTAssertEqual(results.map(\.score), [0, 0, 1, 2])
        XCTAssertEqual(Set(results.map(\.id)).count, 4)
        XCTAssertEqual(try index.search(query: "apple", limit: 1).map(\.word), ["Apple"])
        XCTAssertEqual(try index.search(query: "apple", limit: 3).map(\.score), [0, 0, 1])
        XCTAssertEqual(try index.search(query: " ", limit: 50), [])
        XCTAssertEqual(try index.search(query: "not-present", limit: 50), [])
        XCTAssertThrowsError(try index.search(query: "apple", limit: 0))
        XCTAssertThrowsError(try index.search(query: "apple", limit: -1))
    }

    func testShortQueriesDoNotMatchSubstrings() throws {
        let index = try DictionaryIndex(data: Data(fixture.utf8))
        XCTAssertEqual(try index.search(query: "ap", limit: 50).map(\.word), ["Apple", "apple", "applesauce"])
        XCTAssertEqual(try index.search(query: "app", limit: 50).map(\.word), ["Apple", "apple", "applesauce", "pineapple"])
    }

    func testUTF8ByteOffsetsCRLFAndFinalEntryWithoutNewline() async throws {
        let text = fixture.replacingOccurrences(of: "\n", with: "\r\n")
        let data = Data(text.utf8)
        let store = DictionaryStore(data: data)
        let results = try await store.search(query: "apple")
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.offset, 0)
        XCTAssertEqual(first.ipa, "/apple/")
        XCTAssertEqual(first.preview, "quả táo")
        XCTAssertEqual(first.partOfSpeech, "second section")
        let meaning = try await store.loadMeaning(for: first)
        XCTAssertTrue(meaning.hasPrefix("* noun"))
        XCTAssertTrue(meaning.contains("một quả táo"))
        XCTAssertFalse(meaning.contains("@apple"))

        let lastResults = try await store.search(query: "last")
        let last = try XCTUnwrap(lastResults.first)
        XCTAssertEqual(last.offset + last.length, data.count)
        let lastMeaning = try await store.loadMeaning(for: last)
        XCTAssertEqual(lastMeaning, "plain content without a section")
        let noIPAResults = try await store.search(query: "applesauce")
        XCTAssertEqual(noIPAResults.first?.ipa, "")
        XCTAssertEqual(noIPAResults.first?.partOfSpeech, "")
    }

    func testDefinitionFormattingPreservesUnsectionedContentAndMarkers() {
        let lines = DefinitionLine.parse("plain text\n* noun\n- meaning\n=example+ translation\n!idiom\n\n- ")
        XCTAssertEqual(lines.map(\.text), ["plain text", "noun", "meaning", "example+ translation", "idiom"])
        XCTAssertEqual(lines.map(\.kind), [.note, .heading, .meaning, .meaning, .example])
        XCTAssertEqual(Set(lines.map(\.id)).count, lines.count)
        XCTAssertEqual(DefinitionLine.parse(" \n"), [])
    }

    func testMissingCorruptAndUnreadableResourcesThrowExplicitErrors() async {
        for store in [
            DictionaryStore(resourceURL: nil),
            DictionaryStore(data: Data("not a dictionary".utf8)),
            DictionaryStore(resourceURL: URL(fileURLWithPath: "/missing-dictionary.dict"))
        ] {
            do {
                _ = try await store.search(query: "apple")
                XCTFail("Invalid dictionary must not look like a successful empty search.")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testOutOfBoundsAndForgedEntriesAreRejected() async throws {
        let store = DictionaryStore(data: Data(fixture.utf8))
        for offset in [-1, Int.max, 1] {
            let entry = DictionaryEntry(
                word: "Apple", ipa: "", preview: "", partOfSpeech: "",
                offset: offset, length: Int.max, score: 0
            )
            do {
                _ = try await store.loadMeaning(for: entry)
                XCTFail("Invalid byte ranges must be rejected.")
            } catch DictionaryError.invalidEntry {
            }
        }
    }

    func testCancelledSearchDoesNotPublishResultsAndCanRetry() async throws {
        let store = DictionaryStore(data: Data(fixture.utf8))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.search(query: "apple")
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled search must throw.")
        } catch is CancellationError {
        }
        let results = try await store.search(query: "apple")
        XCTAssertEqual(results.count, 4)
        let cachedTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.search(query: "apple", limit: 1)
        }
        do {
            _ = try await cachedTask.value
            XCTFail("A cancelled exact match must not bypass cancellation.")
        } catch is CancellationError {
        }
    }

    func testFailedInitializationCanRetryAfterResourceIsRestored() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dict")
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        let store = DictionaryStore(resourceURL: url)
        do {
            _ = try await store.search(query: "apple")
            XCTFail("The initial missing resource must fail.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        try Data(fixture.utf8).write(to: url)
        let results = try await store.search(query: "apple")
        XCTAssertEqual(results.count, 4)
    }

    func testBundledDictionaryMatchesFlutterReferenceResults() async throws {
        let store = DictionaryStore()
        let count = try await store.entryCount()
        // Includes the BOM-prefixed metadata header, but not the empty @ header.
        XCTAssertEqual(count, 108856)
        let cases: [(String, [String], [Int])] = [
            ("apple", ["apple", "apple-brandy", "apple-butter", "apple-cart", "apple-cheecked"],
             [417966, 418421, 418480, 418558, 418684]),
            ("hello", ["hello", "phelloderm", "phellogen", "phellodermal", "phellogenetic"],
             [4061095, 6531644, 6531717, 13076387, 13076418]),
            ("computer", ["computer", "computer", "computer", "computerize", "computer analyst"],
             [1644433, 10689697, 14269482, 1644539, 10689800]),
            ("ppy", ["chappy", "chippy", "choppy", "dippy", "gappy"],
             [1319338, 1373230, 1387005, 2337602, 3595139]),
            ("xy", ["xylem", "xylocarp", "xylocarpous", "xylograph", "xylographer"],
             [10502261, 10502335, 10502432, 10502518, 10502579])
        ]
        for (query, words, offsets) in cases {
            let results = try await store.search(query: query, limit: 5)
            XCTAssertEqual(results.map(\.word), words, query)
            XCTAssertEqual(results.map(\.offset), offsets, query)
        }
        let appleResults = try await store.search(query: "apple")
        let apple = try XCTUnwrap(appleResults.first)
        XCTAssertEqual(apple.ipa, "/'æpl/")
        XCTAssertEqual(apple.preview, "quả táo")
        XCTAssertEqual(apple.partOfSpeech, "danh từ")
        let meaning = try await store.loadMeaning(for: apple)
        XCTAssertTrue(meaning.contains("!Adam's apple"))
        XCTAssertTrue(meaning.contains("con sâu bỏ rầu nồi canh"))
        XCTAssertFalse(meaning.contains("@apple-brandy"))
        let limited = try await store.search(query: "co")
        XCTAssertEqual(limited.count, 50)
    }
}
