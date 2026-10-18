import XCTest

final class NavigationTests: XCTestCase {
    func testLaunchAndSwitchBetweenAllTabs() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))

        for title in ["World", "List word to push", "Search", "Setting"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.exists)
            tab.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if title == "World" {
                XCTAssertTrue(app.textFields["worldSearchField"].exists)
                XCTAssertTrue(app.buttons["addWord"].exists)
            } else if title == "Search" {
                XCTAssertTrue(app.textFields["dictionarySearchField"].exists)
            } else if title == "List word to push" {
                XCTAssertTrue(app.buttons["pushSettingsToggle"].exists)
                XCTAssertFalse(app.buttons["reminderInterval"].exists)
                XCTAssertTrue(app.buttons["startPractice"].exists)
                let list = app.collectionViews["pushWordList"]
                for _ in 0..<5 {
                    if app.staticTexts["Home-screen widgets are not migrated yet."].exists { break }
                    list.swipeUp()
                }
                XCTAssertTrue(app.staticTexts["Home-screen widgets are not migrated yet."].exists)
            } else {
                XCTAssertTrue(app.buttons["settingsLanguage"].exists)
                app.swipeUp()
                XCTAssertTrue(app.buttons["settingsDatabase"].exists)
            }
        }
    }

    func testOfflineSearchAndFullDefinition() {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Search"].tap()

        let search = app.textFields["dictionarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("apple")

        let result = app.buttons["dictionaryResult-417966"]
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        result.tap()
        XCTAssertTrue(app.navigationBars["apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["quả táo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["danh từ"].exists)
        XCTAssertTrue(app.buttons["pronounceNormal"].exists)
        XCTAssertTrue(app.buttons["pronounceSlow"].exists)
        XCTAssertTrue(app.buttons["pronounceStop"].exists)
        XCTAssertFalse(app.buttons["pronounceStop"].isEnabled)
        app.buttons["pronounceSlow"].tap()
        XCTAssertTrue(app.staticTexts["Apple text-to-speech (English US)"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["pronunciationError"].exists)
        XCTAssertFalse(app.buttons["pronounceStop"].isEnabled)
        app.buttons["pronounceNormal"].tap()
        XCTAssertTrue(app.staticTexts["Apple text-to-speech (English US)"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["pronunciationError"].exists)

        app.navigationBars.buttons["Search"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pronounceStop"].exists)
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        search.typeText("zzzznotaword")
        XCTAssertTrue(app.staticTexts["No words found"].waitForExistence(timeout: 10))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zzzznotaword".count))
        search.typeText("z")
        XCTAssertTrue(app.staticTexts["Type at least 2 characters to search words"].waitForExistence(timeout: 5))
    }
}
