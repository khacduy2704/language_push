import Foundation

struct DefinitionLine: Identifiable, Equatable {
    enum Kind {
        case heading
        case meaning
        case example
        case note
    }

    let id: Int
    let text: String
    let kind: Kind
    let partOfSpeech: String

    static func parse(_ definition: String) -> [DefinitionLine] {
        var partOfSpeech = "None"
        return definition.components(separatedBy: "\n").enumerated().compactMap { index, raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let kind: Kind
            switch line.first {
            case "*": kind = .heading
            case "-", "=": kind = .meaning
            case "!": kind = .example
            default: kind = .note
            }
            let content = kind == .note ? line : String(line.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            if kind == .heading { partOfSpeech = content }
            return DefinitionLine(id: index, text: content, kind: kind, partOfSpeech: partOfSpeech)
        }
    }
}
