import XCTest
@testable import PushLanguage

@MainActor
final class SettingsTests: XCTestCase {
    private func preferences() throws -> UserDefaults {
        let suite = "settings-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            AppLocalization.language = .english
        }
        return defaults
    }

    func testDefaultLanguageAndPersistenceDoNotChangeReminderInterval() throws {
        let defaults = try preferences()
        defaults.set(20, forKey: "reminderIntervalMinutes")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.language, .english)
        XCTAssertNil(settings.errorMessage)
        settings.setLanguage(.vietnamese)
        XCTAssertEqual(settings.language, .vietnamese)
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "vi")
        XCTAssertEqual(defaults.integer(forKey: "reminderIntervalMinutes"), 20)
        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.language, .vietnamese)
        XCTAssertEqual(AppLocalization.language, .vietnamese)
        reopened.setLanguage(.english)
        XCTAssertEqual(AppLocalization.language, .english)
    }

    func testInvalidStoredLanguageIsReportedAndRepairable() throws {
        for invalid in ["unsupported", 42] as [Any] {
            let defaults = try preferences()
            defaults.set(invalid, forKey: "appLanguage")
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.language, .english)
            XCTAssertNotNil(settings.errorMessage)
            XCTAssertNotNil(defaults.object(forKey: "appLanguage"))
            settings.setLanguage(.vietnamese)
            XCTAssertNil(settings.errorMessage)
            XCTAssertEqual(defaults.string(forKey: "appLanguage"), "vi")
        }
    }

    func testVietnameseTranslationsAndFormattingPreserveData() throws {
        _ = try preferences()
        AppLocalization.language = .vietnamese
        XCTAssertEqual(AppLocalization.text("World"), "Từ đã lưu")
        XCTAssertEqual(AppLocalization.text("Setting"), "Cài đặt")
        XCTAssertEqual(AppLocalization.text("Practice"), "Luyện tập")
        XCTAssertEqual(AppLocalization.format("50 reminders scheduled, every %d min.", 10),
                       "Đã lên lịch 50 lời nhắc, mỗi 10 phút.")
        XCTAssertEqual(AppLocalization.format("Could not save word. %@", WordStorageError.emptyWord.localizedDescription),
                       "Không thể lưu từ. Nhập từ trước khi lưu.")
        XCTAssertEqual(PracticeError.emptyWords.localizedDescription,
                       "Chưa có từ trong danh sách nhắc để luyện tập.")
        XCTAssertEqual(AppLocalization.text("Hello", language: .english), "Hello")
        XCTAssertEqual(AppLocalization.text("World", language: .english), "World")
        XCTAssertEqual(PronunciationError.emptyWord.localizedDescription, "Nhập từ để phát âm.")
        XCTAssertEqual(AppLocalization.text("Reminder hours"), "Khung giờ nhắc từ")
        XCTAssertEqual(AppLocalization.text("All day"), "Cả ngày")
        XCTAssertEqual(AppLocalization.text("To Learn"), "Cần học")
        XCTAssertEqual(AppLocalization.text("Mastered"), "Đã thuộc")
        XCTAssertEqual(AppLocalization.format("Practice score: %lld/5", 4), "Điểm luyện tập: 4/5")
        XCTAssertEqual(ReminderError.invalidTimeWindow.localizedDescription,
                       "Chọn giờ bắt đầu và kết thúc khác nhau, trong khoảng 00:00 đến 23:59.")
    }

    func testEveryVietnameseFormatKeepsEnglishPlaceholders() throws {
        _ = try preferences()
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "Localizable", withExtension: "strings", subdirectory: "vi.lproj"
        ))
        let data = try Data(contentsOf: url)
        let translations = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
        XCTAssertGreaterThan(translations.count, 120)
        let regex = try NSRegularExpression(pattern: "%(?:lld|d|@)")
        func placeholders(_ value: String) -> [String] {
            let range = NSRange(value.startIndex..., in: value)
            return regex.matches(in: value, range: range).compactMap {
                Range($0.range, in: value).map { String(value[$0]) }
            }
        }
        for (key, translated) in translations {
            XCTAssertEqual(placeholders(key), placeholders(translated), key)
            XCTAssertFalse(translated.isEmpty, key)
        }
    }

    func testLocationReportsRealPathWithoutOpeningOrSeedingDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.db")
        let store = WordStore(databaseURL: url)
        let location = try await store.location()
        XCTAssertEqual(location, url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let words = try await store.words()
        XCTAssertEqual(words.count, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let after = try await store.location()
        XCTAssertEqual(after, location)
    }
}
