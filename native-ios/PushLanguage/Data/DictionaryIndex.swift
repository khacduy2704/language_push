import Foundation

struct DictionaryIndex {
    struct Record {
        let word: String
        let lowerWord: String
        let ipa: String
        let preview: String
        let partOfSpeech: String
        let offset: Int
        let length: Int

        func result(score: Int) -> DictionaryEntry {
            DictionaryEntry(
                word: word, ipa: ipa, preview: preview, partOfSpeech: partOfSpeech,
                offset: offset, length: length, score: score
            )
        }
    }

    let records: [Record]
    let exactMatches: [String: [Int]]

    init(data: Data) throws {
        var records: [Record] = []
        var exactMatches: [String: [Int]] = [:]
        var entryStart: Int?
        var word = ""
        var ipa = ""
        var preview = ""
        var partOfSpeech = ""

        func flush(at end: Int) {
            guard let start = entryStart, !word.isEmpty, end > start else { return }
            exactMatches[word.lowercased(), default: []].append(records.count)
            records.append(Record(
                word: word, lowerWord: word.lowercased(), ipa: ipa,
                preview: preview, partOfSpeech: partOfSpeech,
                offset: start, length: end - start
            ))
        }

        // Offsets must count UTF-8 bytes, not Swift characters.
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var lineStart = 0
            var lineCount = 0
            for position in 0...bytes.count {
                guard position == bytes.count || bytes[position] == 10 else { continue }
                var line = String(decoding: bytes[lineStart..<position], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if lineStart == 0 {
                    line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
                }
                if line.hasPrefix("@") {
                    flush(at: lineStart)
                    entryStart = lineStart
                    preview = ""
                    partOfSpeech = ""
                    let header = String(line.dropFirst())
                    if let first = header.firstIndex(of: "/"),
                       let last = header.lastIndex(of: "/"), first < last {
                        word = String(header[..<first]).trimmingCharacters(in: .whitespaces)
                        ipa = String(header[first...last]).trimmingCharacters(in: .whitespaces)
                    } else {
                        word = header.trimmingCharacters(in: .whitespaces)
                        ipa = ""
                    }
                } else if line.hasPrefix("*") {
                    partOfSpeech = Self.field(String(line.dropFirst()))
                } else if preview.isEmpty && (line.hasPrefix("-") || line.hasPrefix("=")) {
                    preview = Self.field(String(line.dropFirst()))
                }
                lineStart = position + 1
                lineCount += 1
                if lineCount % 6000 == 0 {
                    try Task.checkCancellation()
                }
            }
        }
        flush(at: data.count)
        guard !records.isEmpty else { throw DictionaryError.noEntries }
        self.records = records
        self.exactMatches = exactMatches
    }

    private static func field(_ value: String) -> String {
        value.replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search(query: String, limit: Int) throws -> [DictionaryEntry] {
        guard limit > 0 else { throw DictionaryError.invalidLimit }
        try Task.checkCancellation()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        var results: [DictionaryEntry] = []

        for index in exactMatches[query] ?? [] {
            results.append(records[index].result(score: 0))
            if results.count == limit { return results }
        }
        for (index, record) in records.enumerated() {
            if index % 12000 == 0 { try Task.checkCancellation() }
            if record.lowerWord != query && record.lowerWord.hasPrefix(query) {
                results.append(record.result(score: 1))
                if results.count == limit { return results }
            }
        }
        // Dart's String.length counts UTF-16 code units.
        if query.utf16.count >= 3 {
            for (index, record) in records.enumerated() {
                if index % 12000 == 0 { try Task.checkCancellation() }
                if record.lowerWord != query && !record.lowerWord.hasPrefix(query)
                    && record.lowerWord.contains(query) {
                    results.append(record.result(score: 2))
                    if results.count == limit { return results }
                }
            }
        }
        return results
    }
}
