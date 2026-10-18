import AVFoundation

@MainActor
final class AppleSpeechDriver: NSObject, SpeechDriving, AVSpeechSynthesizerDelegate {
    var onEvent: ((SpeechEvent) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var sessionActive = false
    private var requests: [ObjectIdentifier: UUID] = [:]
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.onEvent?(.interrupted)
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func speak(_ word: String, speed: PronunciationSpeed, id: UUID) throws {
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else {
            throw PronunciationError.voiceUnavailable
        }
        // Playback remains audible with the silent switch on; no background audio is enabled.
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        sessionActive = true
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = voice
        utterance.rate = Self.rate(for: speed)
        utterance.pitchMultiplier = 1
        requests[ObjectIdentifier(utterance)] = id
        synthesizer.speak(utterance)
    }

    static func rate(for speed: PronunciationSpeed) -> Float {
        speed == .normal ? AVSpeechUtteranceDefaultSpeechRate : AVSpeechUtteranceDefaultSpeechRate * 0.55
    }

    func stop() throws {
        requests.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        if sessionActive {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            sessionActive = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let id = self.requests.removeValue(forKey: key) else { return }
            self.onEvent?(.finished(id))
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let id = self.requests.removeValue(forKey: key) else { return }
            self.onEvent?(.cancelled(id))
        }
    }
}
