import XCTest

final class PracticeTests: XCTestCase {
    func testFiveCorrectSessionsAutomaticallyMasterAndRemoveWord() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launchEnvironment["PUSH_LANGUAGE_TEST_NOTIFICATION_PERMISSION"] = "allowed"
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.buttons["savedWord-3"].tap()
        app.buttons["pushMembership"].tap()
        XCTAssertTrue(app.buttons["Remove from Push List"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["World"].tap()
        app.tabBars.buttons["List word to push"].tap()
        for score in 1...5 {
            app.buttons["startPractice"].tap()
            XCTAssertTrue(app.navigationBars["Practice"].waitForExistence(timeout: 5))
            let answer = app.textFields["practiceAnswer"]
            if answer.exists {
                answer.tap()
                answer.typeText("Beautiful")
                app.buttons["practiceCheck"].tap()
            } else {
                app.buttons["practiceOption-0"].tap()
            }
            XCTAssertTrue(app.staticTexts["practiceScore"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["practiceScore"].label, "Practice score: \(score)/5")
            if score == 5 {
                XCTAssertTrue(app.staticTexts["practiceMastered"].exists)
            }
            app.buttons["practiceContinue"].tap()
            XCTAssertTrue(app.navigationBars["List word to push"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["No words selected for push yet."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pushWord-3"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["savedWord-3"].exists)
        app.segmentedControls["worldLearningStatus"].buttons["Mastered"].tap()
        XCTAssertTrue(app.buttons["savedWord-3"].waitForExistence(timeout: 5))
        app.buttons["savedWord-3"].tap()
        XCTAssertTrue(app.staticTexts["Correct answers: 5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Incorrect answers: 0"].exists)
        XCTAssertEqual(app.buttons["wordMastery"].label, "Learn Again")
    }

    func testIncorrectAnswersUseBothModesAndFinishWithoutChangingPushWords() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        for id in [1, 3] {
            app.buttons["savedWord-\(id)"].tap()
            XCTAssertTrue(app.buttons["pushMembership"].waitForExistence(timeout: 5))
            app.buttons["pushMembership"].tap()
            XCTAssertTrue(app.buttons["Remove from Push List"].waitForExistence(timeout: 5))
            app.navigationBars.buttons["World"].tap()
        }
        app.tabBars.buttons["List word to push"].tap()
        app.buttons["startPractice"].tap()
        XCTAssertTrue(app.navigationBars["Practice"].waitForExistence(timeout: 5))
        var typingTurns = 0
        var flashTurns = 0
        for turn in 0..<4 {
            let answer = app.textFields["practiceAnswer"]
            if answer.exists {
                typingTurns += 1
                answer.tap()
                answer.typeText("zz")
                app.buttons["practiceCheck"].tap()
            } else {
                flashTurns += 1
                let target = app.staticTexts["A greeting (n)"].exists ? "Hello" : "Beautiful"
                let options = (0..<4).map { app.buttons["practiceOption-\($0)"] }
                guard let wrong = options.first(where: { $0.label != target }) else {
                    return XCTFail("Two distinct headwords should provide a distractor.")
                }
                wrong.tap()
            }
            XCTAssertTrue(app.staticTexts["Incorrect"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["practiceContinue"].label, turn == 3 ? "Finish" : "Continue")
            app.buttons["practiceContinue"].tap()
        }
        XCTAssertEqual(typingTurns, 2)
        XCTAssertEqual(flashTurns, 2)
        XCTAssertTrue(app.navigationBars["List word to push"].waitForExistence(timeout: 5))
        assertPushWord(1, in: app)
        assertPushWord(3, in: app)
        app.tabBars.buttons["World"].tap()
        app.buttons["savedWord-3"].tap()
        XCTAssertTrue(app.staticTexts["Incorrect answers: 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["wordPracticeScore"].label, "Practice score: 0/5")
        XCTAssertTrue(app.staticTexts["Correct answers: 0"].exists)
    }

    func testEmptySelectionAndCompletingSnapshotSession() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.tabBars.buttons["List word to push"].tap()
        app.buttons["startPractice"].tap()
        XCTAssertTrue(app.staticTexts["No words in push list to practice."].waitForExistence(timeout: 5))

        app.tabBars.buttons["World"].tap()
        app.buttons["savedWord-1"].tap()
        XCTAssertTrue(app.buttons["pushMembership"].waitForExistence(timeout: 5))
        app.buttons["pushMembership"].tap()
        XCTAssertTrue(app.buttons["Remove from Push List"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["World"].tap()
        app.tabBars.buttons["List word to push"].tap()
        app.buttons["startPractice"].tap()
        XCTAssertTrue(app.navigationBars["Practice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A greeting (n)"].exists)

        let answer = app.textFields["practiceAnswer"]
        if answer.exists {
            XCTAssertFalse(app.buttons["practiceCheck"].isEnabled)
            answer.tap()
            answer.typeText("hello")
            app.buttons["practiceCheck"].tap()
        } else {
            XCTAssertTrue(app.buttons["practiceOption-0"].exists)
            app.buttons["practiceOption-0"].tap()
        }
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Finish"].exists)
        app.buttons["practiceContinue"].tap()
        XCTAssertTrue(app.navigationBars["List word to push"].waitForExistence(timeout: 5))
        assertPushWord(1, in: app)
        app.buttons["startPractice"].tap()
        XCTAssertTrue(app.navigationBars["Practice"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["List word to push"].tap()
        assertPushWord(1, in: app)
    }

    private func assertPushWord(_ id: Int, in app: XCUIApplication) {
        let word = app.buttons["pushWord-\(id)"]
        for _ in 0..<5 {
            if word.exists { break }
            app.collectionViews["pushWordList"].swipeUp()
        }
        XCTAssertTrue(word.waitForExistence(timeout: 5))
    }
}
