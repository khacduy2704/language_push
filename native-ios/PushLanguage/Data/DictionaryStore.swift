import Foundation

actor DictionaryStore {
    private let resourceURL: URL?
    private var data: Data?
    private var index: DictionaryIndex?

    init(resourceURL: URL? = Bundle.main.url(forResource: "anhviet109K", withExtension: "dict")) {
        self.resourceURL = resourceURL
    }

    init(data: Data) {
        self.resourceURL = nil
        self.data = data
    }

    private func prepare() throws {
        try Task.checkCancellation()
        if index != nil { return }
        let loadedData: Data
        if let data {
            loadedData = data
        } else {
            guard let resourceURL else { throw DictionaryError.missingResource }
            loadedData = try Data(contentsOf: resourceURL, options: .mappedIfSafe)
        }
        let loadedIndex = try DictionaryIndex(data: loadedData)
        try Task.checkCancellation()
        data = loadedData
        index = loadedIndex
    }

    func search(query: String, limit: Int = 50) throws -> [DictionaryEntry] {
        try prepare()
        guard let index else { throw DictionaryError.noEntries }
        return try index.search(query: query, limit: limit)
    }

    func entryCount() throws -> Int {
        try prepare()
        guard let index else { throw DictionaryError.noEntries }
        return index.records.count
    }

    func loadMeaning(for entry: DictionaryEntry) throws -> String {
        try prepare()
        guard let data, let index,
              entry.offset >= 0, entry.length > 0,
              entry.offset <= data.count, entry.length <= data.count - entry.offset,
              let recordIndex = index.exactMatches[entry.word.lowercased()]?.first(where: {
                  index.records[$0].offset == entry.offset && index.records[$0].length == entry.length
              }) else {
            throw DictionaryError.invalidEntry
        }
        let record = index.records[recordIndex]
        let raw = String(decoding: data[record.offset..<(record.offset + record.length)], as: UTF8.self)
        var lines = raw.components(separatedBy: "\n")
        if let first = lines.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")).hasPrefix("@") {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
