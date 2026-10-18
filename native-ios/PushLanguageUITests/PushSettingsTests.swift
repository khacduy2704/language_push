import XCTest

final class PushSettingsTests: XCTestCase {
    func testSettingsCollapseExpandAndKeepUpdatedSummary() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launchEnvironment["PUSH_LANGUAGE_TEST_NOTIFICATION_PERMISSION"] = "allowed"
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.buttons["savedWord-1"].tap()
        app.buttons["pushMembership"].tap()
        XCTAssertTrue(app.buttons["Remove from Push List"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["World"].tap()
        app.tabBars.buttons["List word to push"].tap()

        let toggle = app.buttons["pushSettingsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertTrue(toggle.label.contains("07:00 - 20:00"))
        XCTAssertFalse(app.buttons["reminderInterval"].exists)
        XCTAssertFalse(app.buttons["reminderWordCount"].exists)
        XCTAssertFalse(app.buttons["reminderTimeWindow"].exists)
        XCTAssertTrue(app.buttons["pushWord-1"].isHittable)

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Expanded")
        XCTAssertTrue(app.buttons["reminderInterval"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminderTimeWindow"].exists)
        app.buttons["reminderWordCount"].tap()
        app.buttons["2"].tap()
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertTrue(toggle.label.contains("2 words"))
        XCTAssertFalse(app.buttons["reminderWordCount"].exists)
        XCTAssertTrue(app.buttons["pushWord-1"].isHittable)

        app.tabBars.buttons["Setting"].tap()
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        app.tabBars.buttons["Danh sách nhắc từ"].tap()
        XCTAssertTrue(toggle.label.contains("Cài đặt nhắc từ"))
        XCTAssertTrue(toggle.label.contains("2 từ"))
        toggle.tap()
        XCTAssertTrue(app.buttons["reminderWordCount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminderWordCount"].label.contains("2"))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Từ đã lưu"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Danh sách nhắc từ"].tap()
        XCTAssertEqual(toggle.value as? String, "Đang thu gọn")
        XCTAssertTrue(toggle.label.contains("2 từ"))
        XCTAssertFalse(app.buttons["reminderWordCount"].exists)
    }
}
