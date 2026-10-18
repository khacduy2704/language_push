import XCTest

final class SettingsTests: XCTestCase {
    func testWordsPerReminderSharedBetweenTabsPersistsAndIsTranslated() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launchEnvironment["PUSH_LANGUAGE_TEST_NOTIFICATION_PERMISSION"] = "allowed"
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.tabBars.buttons["List word to push"].tap()
        app.buttons["pushSettingsToggle"].tap()
        let count = app.buttons["reminderWordCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.contains("5"))
        count.tap()
        for value in ["1", "2", "3", "4", "5"] {
            XCTAssertTrue(app.buttons[value].exists)
        }
        app.buttons["2"].tap()
        app.tabBars.buttons["Setting"].tap()
        XCTAssertTrue(count.label.contains("2"))
        count.tap()
        app.buttons["4"].tap()
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertTrue(count.label.contains("Số từ mỗi lần nhắc"))
        app.tabBars.buttons["Danh sách nhắc từ"].tap()
        XCTAssertTrue(count.label.contains("4"))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Từ đã lưu"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Danh sách nhắc từ"].tap()
        app.buttons["pushSettingsToggle"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.contains("4"))
        XCTAssertTrue(app.buttons["reminderInterval"].label.contains("10"))
    }

    func testLanguageSwitchPersistenceDatabaseAndSharedInterval() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Setting"].tap()
        XCTAssertTrue(app.buttons["settingsLanguage"].waitForExistence(timeout: 5))
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Từ đã lưu"].exists)
        app.buttons["settingsInterval"].tap()
        app.buttons["20 phút"].tap()
        app.tabBars.buttons["Danh sách nhắc từ"].tap()
        app.buttons["pushSettingsToggle"].tap()
        XCTAssertTrue(app.buttons["reminderInterval"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminderInterval"].label.contains("20"))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Từ đã lưu"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Cài đặt"].tap()
        XCTAssertTrue(app.buttons["settingsInterval"].label.contains("20"))
        app.swipeUp()
        app.buttons["settingsDatabase"].tap()
        XCTAssertTrue(app.navigationBars["Vị trí cơ sở dữ liệu"].waitForExistence(timeout: 5))
        let path = app.staticTexts["databasePath"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        XCTAssertTrue(path.label.contains("ui-test-"))
        XCTAssertTrue(path.label.hasSuffix(".db"))
        app.navigationBars.buttons["Cài đặt"].tap()
        app.swipeDown()
        app.buttons["settingsLanguage"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Setting"].waitForExistence(timeout: 5))
        app.tabBars.buttons["World"].tap()
        app.buttons["savedWord-1"].tap()
        XCTAssertTrue(app.staticTexts["A greeting"].waitForExistence(timeout: 5))
    }

    func testVietnameseFormValidationAndPracticeErrorsAreTranslated() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Setting"].tap()
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        app.tabBars.buttons["Từ đã lưu"].tap()
        app.buttons["addWord"].tap()
        XCTAssertTrue(app.navigationBars["Thêm từ"].waitForExistence(timeout: 5))
        app.buttons["wordFormSave"].tap()
        XCTAssertTrue(app.staticTexts["Không thể lưu từ. Nhập từ trước khi lưu."].waitForExistence(timeout: 5))
        app.buttons["Hủy"].tap()
        app.tabBars.buttons["Danh sách nhắc từ"].tap()
        app.buttons["startPractice"].tap()
        XCTAssertTrue(app.staticTexts["Chưa có từ trong danh sách nhắc để luyện tập."].waitForExistence(timeout: 5))
    }
}
