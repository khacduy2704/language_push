import XCTest
@testable import PushLanguage

final class AppTabTests: XCTestCase {
    func testTabsMatchFlutterNavigationOrderAndLabels() {
        XCTAssertEqual(
            AppTab.allCases.map(\.title),
            ["World", "List word to push", "Search", "Setting"]
        )
        XCTAssertEqual(Set(AppTab.allCases.map(\.id)).count, 4)
        XCTAssertEqual(AppTab.allCases.first, .world)
    }

    func testEveryTabExplainsItsUnmigratedFeatures() {
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.symbol.isEmpty)
            XCTAssertTrue(tab.migrationMessage.contains("have not been migrated yet"))
        }
    }
}
