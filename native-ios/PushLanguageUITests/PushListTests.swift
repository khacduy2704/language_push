import XCTest

final class PushListTests: XCTestCase {
    func testUnlimitedMembershipWorldIndicatorsPersistenceAndConfirmedRemoval() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))

        for id in [3, 5, 9, 7, 1, 4] {
            let row = app.buttons["savedWord-\(id)"]
            for _ in 0..<3 {
                if row.exists && row.isHittable { break }
                app.cells.firstMatch.swipeUp()
            }
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            XCTAssertEqual(row.value as? String, "Not in Push List")
            row.tap()
            let membership = app.buttons["pushMembership"]
            XCTAssertTrue(membership.waitForExistence(timeout: 5))
            membership.tap()
            XCTAssertTrue(app.buttons["Remove from Push List"].waitForExistence(timeout: 5))
            app.navigationBars.buttons["World"].tap()
            let updated = NSPredicate(format: "value == %@", "In Push List")
            expectation(for: updated, evaluatedWith: row)
            waitForExpectations(timeout: 5)
        }

        app.tabBars.buttons["List word to push"].tap()
        XCTAssertTrue(app.staticTexts["notificationPermissionReminder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open iOS Settings"].exists)
        assertPushWords([3, 5, 9, 7, 1, 4], in: app)
        let row = app.cells.containing(.button, identifier: "pushWord-3").firstMatch
        row.swipeLeft()
        app.buttons["Remove"].tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["pushWord-3"].exists)
        row.swipeLeft()
        app.buttons["Remove"].tap()
        app.alerts.buttons["Remove"].tap()
        XCTAssertFalse(app.buttons["pushWord-3"].waitForExistence(timeout: 2))

        app.terminate()
        app.launch()
        app.tabBars.buttons["List word to push"].tap()
        XCTAssertTrue(app.collectionViews["pushWordList"].waitForExistence(timeout: 10))
        assertPushWords([5, 9, 7, 1, 4], in: app)
        XCTAssertFalse(app.buttons["pushWord-3"].exists)
        app.tabBars.buttons["World"].tap()
        XCTAssertTrue(app.buttons["savedWord-3"].exists)
        XCTAssertEqual(app.buttons["savedWord-3"].value as? String, "Not in Push List")
        XCTAssertEqual(app.buttons["savedWord-5"].value as? String, "In Push List")
        app.buttons["clearAllWords"].tap()
        app.alerts.buttons["Remove All"].tap()
        app.tabBars.buttons["List word to push"].tap()
        app.buttons["pushSettingsToggle"].tap()
        XCTAssertTrue(app.staticTexts["No words selected for push yet."].waitForExistence(timeout: 5))
    }

    private func assertPushWords(_ ids: [Int], in app: XCUIApplication) {
        let list = app.collectionViews["pushWordList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for id in ids {
            let word = app.buttons["pushWord-\(id)"]
            for _ in 0..<12 {
                if word.exists { break }
                list.swipeUp(velocity: .fast)
            }
            XCTAssertTrue(word.waitForExistence(timeout: 5))
        }
        if let first = ids.first {
            for _ in 0..<12 {
                let row = app.buttons["pushWord-\(first)"]
                if row.exists && row.isHittable { break }
                list.swipeDown(velocity: .fast)
            }
        }
    }
}
