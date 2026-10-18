import XCTest

final class NotificationPermissionTests: XCTestCase {
    private func launch(permission: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launchEnvironment["PUSH_LANGUAGE_TEST_NOTIFICATION_PERMISSION"] = permission
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        return app
    }

    func testDeniedReminderAppearsAcrossTabsWithoutSelectedWordsAndIsTranslated() {
        let app = launch(permission: "denied")
        let message = app.staticTexts["notificationPermissionReminder"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["notificationPermissionSettings"].exists)
        XCTAssertFalse(app.buttons["notificationPermissionEnable"].exists)
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(message.exists)
        app.tabBars.buttons["Setting"].tap()
        XCTAssertTrue(message.exists)
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertEqual(message.label, "Hãy cho phép thông báo để nhận lời nhắc học từ.")
        app.tabBars.buttons["Danh sách nhắc từ"].tap()
        XCTAssertTrue(app.staticTexts["Chưa chọn từ để nhắc."].waitForExistence(timeout: 5))
        XCTAssertTrue(message.exists)
    }

    func testUndeterminedReminderEnablesPermissionAndDisappears() {
        let app = launch(permission: "notDetermined")
        let enable = app.buttons["notificationPermissionEnable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["notificationPermissionSettings"].exists)
        enable.tap()
        let disappeared = NSPredicate(format: "exists == false")
        expectation(for: disappeared, evaluatedWith: app.staticTexts["notificationPermissionReminder"])
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["List word to push"].tap()
        XCTAssertTrue(app.staticTexts["No words selected for push yet."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["notificationPermissionReminder"].exists)
    }

    func testAllowedPermissionDoesNotShowReminder() {
        let app = launch(permission: "allowed")
        app.tabBars.buttons["List word to push"].tap()
        XCTAssertTrue(app.staticTexts["No words selected for push yet."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["notificationPermissionReminder"].exists)
        XCTAssertFalse(app.buttons["notificationPermissionEnable"].exists)
        XCTAssertFalse(app.buttons["notificationPermissionSettings"].exists)
    }
}
