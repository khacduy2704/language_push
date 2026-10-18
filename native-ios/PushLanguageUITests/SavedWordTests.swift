import XCTest

final class SavedWordTests: XCTestCase {
    func testManualMasteryTabsPersistenceAndRelearningRemoveReminders() {
        let app = application()
        let row = app.buttons["savedWord-3"]
        row.tap()
        app.buttons["pushMembership"].tap()
        XCTAssertTrue(app.buttons["Remove from Push List"].waitForExistence(timeout: 5))
        app.buttons["wordMastery"].tap()
        let relearn = app.buttons["wordMastery"]
        expectation(for: NSPredicate(format: "label == %@", "Learn Again"), evaluatedWith: relearn)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["pushMembership"].isEnabled)
        XCTAssertEqual(app.staticTexts["wordPracticeScore"].label, "Practice score: 5/5")
        app.navigationBars.buttons["World"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
        app.segmentedControls["worldLearningStatus"].buttons["Mastered"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.tabBars.buttons["List word to push"].tap()
        XCTAssertTrue(app.staticTexts["No words selected for push yet."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pushWord-3"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        XCTAssertFalse(row.exists)
        app.segmentedControls["worldLearningStatus"].buttons["Mastered"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        relearn.tap()
        expectation(for: NSPredicate(format: "label == %@", "Mark as Mastered"), evaluatedWith: relearn)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.staticTexts["wordPracticeScore"].label, "Practice score: 0/5")
        XCTAssertTrue(app.buttons["pushMembership"].isEnabled)
        XCTAssertEqual(app.buttons["pushMembership"].label, "Add to Push List")
        app.navigationBars.buttons["World"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
        app.segmentedControls["worldLearningStatus"].buttons["To Learn"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.tabBars.buttons["Setting"].tap()
        app.buttons["settingsLanguage"].tap()
        app.buttons["Tiếng Việt"].tap()
        app.tabBars.buttons["Từ đã lưu"].tap()
        XCTAssertTrue(app.segmentedControls["worldLearningStatus"].buttons["Cần học"].exists)
        XCTAssertTrue(app.segmentedControls["worldLearningStatus"].buttons["Đã thuộc"].exists)
        row.tap()
        XCTAssertEqual(relearn.label, "Đã thuộc")
    }

    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PUSH_LANGUAGE_TEST_DATABASE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 10))
        return app
    }

    func testCreateEditPersistDeleteAndClearWithConfirmation() {
        let app = application()
        XCTAssertTrue(app.staticTexts["Beautiful"].waitForExistence(timeout: 10))
        app.buttons["addWord"].tap()
        app.buttons["wordFormSave"].tap()
        XCTAssertTrue(app.staticTexts["Could not save word. Enter a word before saving."].waitForExistence(timeout: 5))
        let word = app.textFields["wordFormWord"]
        word.tap()
        word.typeText("ZebraNativeTest")
        let meaning = app.textViews["wordFormMeaning"]
        meaning.tap()
        meaning.typeText("first meaning")
        app.buttons["wordFormSave"].tap()
        XCTAssertTrue(app.navigationBars["World"].waitForExistence(timeout: 5))

        let search = app.textFields["worldSearchField"]
        search.tap()
        search.typeText("ZebraNativeTest")
        let row = app.cells.containing(.staticText, identifier: "ZebraNativeTest").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Word"].waitForExistence(timeout: 5))
        let edit = app.textViews["wordFormMeaning"]
        edit.tap()
        edit.typeText("edited ")
        guard let editedMeaning = edit.value as? String else {
            return XCTFail("The meaning editor should contain text.")
        }
        XCTAssertTrue(editedMeaning.contains("edited"))
        XCTAssertTrue(editedMeaning.contains("first meaning"))
        app.buttons["wordFormSave"].tap()
        XCTAssertTrue(app.staticTexts["(None) \(editedMeaning)"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["worldSearchField"].waitForExistence(timeout: 10))
        app.textFields["worldSearchField"].tap()
        app.textFields["worldSearchField"].typeText("ZebraNativeTest")
        XCTAssertTrue(app.staticTexts["ZebraNativeTest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["(None) \(editedMeaning)"].exists)
        let persisted = app.cells.containing(.staticText, identifier: "ZebraNativeTest").firstMatch
        persisted.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete Word"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(persisted.exists)
        persisted.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["ZebraNativeTest"].waitForExistence(timeout: 2))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Beautiful"].waitForExistence(timeout: 10))
        app.buttons["clearAllWords"].tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Beautiful"].exists)
        app.buttons["clearAllWords"].tap()
        app.alerts.buttons["Remove All"].tap()
        XCTAssertTrue(app.staticTexts["No saved words. Tap + to add a word."].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No saved words. Tap + to add a word."].waitForExistence(timeout: 10))
    }

    func testDictionaryMeaningSavesOnceAndAppearsInWorldAndSearch() {
        let app = application()
        app.tabBars.buttons["Search"].tap()
        let search = app.textFields["dictionarySearchField"]
        search.tap()
        search.typeText("apple")
        let result = app.buttons["dictionaryResult-417966"]
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        result.tap()
        let save = app.buttons["saveMeaning-1"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.staticTexts["Meaning saved to World."].waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["This meaning is already saved to World."].waitForExistence(timeout: 5))

        app.tabBars.buttons["World"].tap()
        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["(danh từ) quả táo"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "apple").count, 1)

        app.tabBars.buttons["Search"].tap()
        app.navigationBars.buttons["Search"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchSavedWord-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.staticTexts["quả táo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pronounceNormal"].exists)
    }
}
