import AVFoundation
import XCTest
@testable import PushLanguage

@MainActor
final class PronunciationTests: XCTestCase {
    private final class Driver: SpeechDriving {
        var onEvent: ((SpeechEvent) -> Void)?
        var requests: [(word: String, speed: PronunciationSpeed, id: UUID)] = []
        var stopCount = 0
        var speakError: Error?
        var stopError: Error?

        func speak(_ word: String, speed: PronunciationSpeed, id: UUID) throws {
            if let speakError { throw speakError }
            requests.append((word, speed, id))
        }

        func stop() throws {
            stopCount += 1
            if let stopError { throw stopError }
        }
    }

    func testNormalAndSlowPlaybackNormalizeWordsAndReplaceActiveSpeech() {
        let driver = Driver()
        let service = PronunciationService(driver: driver)
        service.play("  APPLE\n", speed: .normal)
        XCTAssertEqual(driver.requests.first?.word, "apple")
        XCTAssertEqual(driver.requests.first?.speed, .normal)
        XCTAssertEqual(service.state, .speaking(.normal))

        service.play("Hello World", speed: .slow)
        XCTAssertEqual(driver.requests.last?.word, "hello world")
        XCTAssertEqual(driver.requests.last?.speed, .slow)
        XCTAssertEqual(driver.stopCount, 2)
        XCTAssertEqual(service.state, .speaking(.slow))
        XCTAssertNotEqual(driver.requests.first?.id, driver.requests.last?.id)
    }

    func testCompletionCancellationAndInterruptionReleaseAudio() throws {
        let driver = Driver()
        let service = PronunciationService(driver: driver)
        service.play("apple", speed: .normal)
        let first = try XCTUnwrap(driver.requests.last?.id)
        driver.onEvent?(.finished(first))
        XCTAssertEqual(service.state, .idle)

        service.play("apple", speed: .slow)
        let second = try XCTUnwrap(driver.requests.last?.id)
        driver.onEvent?(.cancelled(second))
        XCTAssertEqual(service.state, .idle)

        service.play("apple", speed: .normal)
        driver.onEvent?(.interrupted)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(driver.stopCount, 6)
    }

    func testStaleCallbacksCannotStopNewPlaybackOrOverwriteStopFailure() throws {
        let driver = Driver()
        let service = PronunciationService(driver: driver)
        service.play("apple", speed: .normal)
        let oldID = try XCTUnwrap(driver.requests.last?.id)
        service.play("hello", speed: .slow)
        driver.onEvent?(.cancelled(oldID))
        driver.onEvent?(.finished(oldID))
        XCTAssertEqual(service.state, .speaking(.slow))
        XCTAssertEqual(driver.stopCount, 2)

        driver.stopError = NSError(domain: "AudioSession", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Cannot deactivate audio"
        ])
        service.stop()
        guard case .failed(let message) = service.state else {
            return XCTFail("Stopping failures must be visible.")
        }
        XCTAssertTrue(message.contains("Cannot deactivate audio"))
        let latestID = try XCTUnwrap(driver.requests.last?.id)
        driver.onEvent?(.finished(latestID))
        XCTAssertEqual(service.state, .failed(message))
    }

    func testEmptyWordsAndVoiceFailuresAreVisibleAndRetryable() {
        let driver = Driver()
        let service = PronunciationService(driver: driver)
        service.play(" \n", speed: .normal)
        XCTAssertTrue(driver.requests.isEmpty)
        guard case .failed(let emptyMessage) = service.state else {
            return XCTFail("Empty words must report an error.")
        }
        XCTAssertTrue(emptyMessage.contains("Enter a word"))

        driver.speakError = PronunciationError.voiceUnavailable
        service.play("apple", speed: .normal)
        guard case .failed(let voiceMessage) = service.state else {
            return XCTFail("Unavailable speech voices must report an error.")
        }
        XCTAssertTrue(voiceMessage.contains("voice is unavailable"))
        driver.speakError = nil
        service.play("apple", speed: .slow)
        XCTAssertEqual(service.state, .speaking(.slow))
    }

    func testFailedAudioReleasePreventsStartingAnotherUtterance() {
        let driver = Driver()
        driver.stopError = NSError(domain: "AudioSession", code: 1)
        let service = PronunciationService(driver: driver)
        service.play("apple", speed: .normal)
        XCTAssertTrue(driver.requests.isEmpty)
        guard case .failed = service.state else {
            return XCTFail("A failed audio-session operation must not show playback success.")
        }
    }

    func testStopIsSafeWithoutPlaybackAndStaleEventsAreIgnored() {
        let driver = Driver()
        let service = PronunciationService(driver: driver)
        service.stop()
        driver.onEvent?(.interrupted)
        driver.onEvent?(.finished(UUID()))
        XCTAssertEqual(driver.stopCount, 1)
        XCTAssertEqual(service.state, .idle)
    }

    func testAppleRatesAreValidAndSlowIsSlower() {
        let normal = AppleSpeechDriver.rate(for: .normal)
        let slow = AppleSpeechDriver.rate(for: .slow)
        XCTAssertEqual(normal, AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertGreaterThanOrEqual(slow, AVSpeechUtteranceMinimumSpeechRate)
        XCTAssertLessThan(slow, normal)
        XCTAssertLessThanOrEqual(normal, AVSpeechUtteranceMaximumSpeechRate)
    }

    func testAppleSpeechDriverCompletesRealUtterance() async throws {
        let driver = AppleSpeechDriver()
        let id = UUID()
        let finished = expectation(description: "Apple speech synthesis completed")
        driver.onEvent = { event in
            if case .finished(let finishedID) = event {
                XCTAssertEqual(finishedID, id)
                finished.fulfill()
            }
        }
        try driver.speak(
            "This longer pronunciation should stop before the next word is spoken.",
            speed: .slow, id: UUID()
        )
        try driver.stop()
        try driver.speak("apple", speed: .normal, id: id)
        await fulfillment(of: [finished], timeout: 20)
        try driver.stop()
    }
}
