import Foundation
import Combine

enum PronunciationSpeed: String, CaseIterable {
    case normal
    case slow
}

enum SpeechEvent {
    case finished(UUID)
    case cancelled(UUID)
    case interrupted
}

@MainActor
protocol SpeechDriving: AnyObject {
    var onEvent: ((SpeechEvent) -> Void)? { get set }
    func speak(_ word: String, speed: PronunciationSpeed, id: UUID) throws
    func stop() throws
}

enum PronunciationError: LocalizedError {
    case emptyWord
    case voiceUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyWord: return AppLocalization.text("Enter a word to pronounce.")
        case .voiceUnavailable:
            return AppLocalization.text("An English (US) speech voice is unavailable. Check your device's speech voice settings.")
        }
    }
}

@MainActor
final class PronunciationService: ObservableObject {
    enum State: Equatable {
        case idle
        case speaking(PronunciationSpeed)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private let driver: SpeechDriving
    private var activeID: UUID?

    init(driver: SpeechDriving) {
        self.driver = driver
        driver.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    convenience init() {
        self.init(driver: AppleSpeechDriver())
    }

    func play(_ word: String, speed: PronunciationSpeed) {
        do {
            try driver.stop()
            activeID = nil
            let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { throw PronunciationError.emptyWord }
            let id = UUID()
            try driver.speak(normalized, speed: speed, id: id)
            activeID = id
            state = .speaking(speed)
        } catch {
            activeID = nil
            state = .failed(AppLocalization.format("Could not play pronunciation. %@", error.localizedDescription))
        }
    }

    func stop() {
        activeID = nil
        do {
            try driver.stop()
            state = .idle
        } catch {
            state = .failed(AppLocalization.format("Could not release pronunciation audio. %@", error.localizedDescription))
        }
    }

    private func handle(_ event: SpeechEvent) {
        switch event {
        case .finished(let id), .cancelled(let id):
            guard id == activeID else { return }
            stop()
        case .interrupted:
            guard activeID != nil else { return }
            stop()
        }
    }
}
