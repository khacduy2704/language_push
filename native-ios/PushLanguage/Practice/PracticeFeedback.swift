import AVFoundation
import Combine

@MainActor
final class PracticeFeedback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var errorMessage: String?
    private var player: AVAudioPlayer?
    private let session = AVAudioSession.sharedInstance()
    private var active = false
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func play(correct: Bool) {
        do {
            try release()
            errorMessage = nil
            let name = correct ? "correct" : "incorrect"
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
                throw NSError(domain: "PracticeAudio", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: AppLocalization.format("Practice feedback sound %@.mp3 is missing.", name)
                ])
            }
            let player = try AVAudioPlayer(contentsOf: url)
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            active = true
            self.player = player
            player.delegate = self
            guard player.play() else {
                throw NSError(domain: "PracticeAudio", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: AppLocalization.text("The feedback sound could not start.")
                ])
            }
        } catch {
            let playbackError = error.localizedDescription
            do {
                try release()
                errorMessage = AppLocalization.format("Could not play feedback sound. %@", playbackError)
            } catch {
                errorMessage = AppLocalization.format("Could not play feedback sound. %@", "\(playbackError) \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        do {
            try release()
        } catch {
            errorMessage = AppLocalization.format("Could not release feedback audio. %@", error.localizedDescription)
        }
    }

    private func release() throws {
        player?.stop()
        player = nil
        if active {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            active = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let key = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == key else { return }
            self.stop()
            if !flag { self.errorMessage = AppLocalization.text("Feedback audio did not finish successfully.") }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let key = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? AppLocalization.text("The feedback sound could not be decoded.")
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == key else { return }
            self.stop()
            self.errorMessage = AppLocalization.format("Could not decode feedback audio. %@", message)
        }
    }
}
