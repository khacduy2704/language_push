import XCTest

final class AuthenticationTests: XCTestCase {
    func testSetupRequiredIsExplicitAndLocalFeaturesRemainAvailable() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Setting"].tap()
        XCTAssertTrue(app.staticTexts["authSetupRequired"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settingsSignIn"].exists)
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertEqual(app.staticTexts["authSetupRequired"].label, "Cần cấu hình Firebase cho ứng dụng gốc này.")
        app.tabBars.buttons["Từ đã lưu"].tap()
        XCTAssertTrue(app.buttons["savedWord-1"].waitForExistence(timeout: 5))
    }
}
