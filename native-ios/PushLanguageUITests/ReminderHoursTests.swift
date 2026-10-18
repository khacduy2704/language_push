import XCTest

final class ReminderHoursTests: XCTestCase {
    func testEditHoursSharedAcrossTabsPersistsAndCanBeDisabled() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launchEnvironment["PUSH_LANGUAGE_TEST_NOTIFICATION_PERMISSION"] = "allowed"
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.tabBars.buttons["List word to push"].tap()
        app.buttons["pushSettingsToggle"].tap()
        let link = app.buttons["reminderTimeWindow"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("07:00 - 20:00"))
        link.tap()
        XCTAssertTrue(app.switches["reminderHoursEnabled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["reminderHoursEnabled"].value as? String, "1")
        choose("08", picker: "reminderStartHour", in: app)
        choose("05", picker: "reminderStartMinute", in: app)
        choose("21", picker: "reminderEndHour", in: app)
        choose("10", picker: "reminderEndMinute", in: app)
        app.buttons["reminderHoursSave"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("08:05 - 21:10"))

        app.tabBars.buttons["Setting"].tap()
        for _ in 0..<3 {
            if link.exists && link.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(link.label.contains("08:05 - 21:10"))
        link.tap()
        choose("09", picker: "reminderStartHour", in: app)
        app.navigationBars.buttons["Setting"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("08:05 - 21:10"))
        link.tap()
        setLimit(false, in: app)
        XCTAssertFalse(app.buttons["reminderStartHour"].exists)
        app.buttons["reminderHoursSave"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("All day"))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.tabBars.buttons["List word to push"].tap()
        app.buttons["pushSettingsToggle"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("All day"))
        link.tap()
        setLimit(true, in: app)
        XCTAssertTrue(app.buttons["reminderStartHour"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminderStartHour"].label.contains("08"))
        XCTAssertTrue(app.buttons["reminderStartMinute"].label.contains("05"))
        app.buttons["reminderHoursSave"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("08:05 - 21:10"))
        app.tabBars.buttons["Setting"].tap()
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertTrue(link.label.contains("Khung giờ nhắc từ"))
        link.tap()
        XCTAssertTrue(app.navigationBars["Khung giờ nhắc từ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["reminderHoursEnabled"].label.contains("Giới hạn khung giờ nhắc"))
    }

    private func choose(_ value: String, picker: String, in app: XCUIApplication) {
        let control = app.buttons[picker]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
        app.buttons[value].tap()
    }

    private func setLimit(_ enabled: Bool, in app: XCUIApplication) {
        let control = app.switches["reminderHoursEnabled"]
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", enabled ? "1" : "0"), evaluatedWith: control)
        waitForExpectations(timeout: 5)
    }
}
