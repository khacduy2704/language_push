import XCTest
@testable import PushLanguage

final class ReminderTimeWindowTests: XCTestCase {
    private let words = [
        SavedWord(id: 1, word: "Hello", partOfSpeech: "n", meaning: "A greeting", isPushed: true)
    ]

    private func calendar(_ zone: String = "Asia/Ho_Chi_Minh") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    func testStandardWindowBoundariesAndNextDayOpening() throws {
        let calendar = try calendar()
        let window = ReminderTimeWindow.standard
        XCTAssertTrue(window.enabled)
        XCTAssertEqual(window.hoursSummary, "07:00 - 20:00")
        for (start, expected) in [
            ("2026-10-17T06:00:00+07:00", "2026-10-17T07:00:00+07:00"),
            ("2026-10-17T06:50:00+07:00", "2026-10-17T07:00:00+07:00"),
            ("2026-10-17T07:00:00+07:00", "2026-10-17T07:10:00+07:00"),
            ("2026-10-17T19:49:00+07:00", "2026-10-17T19:59:00+07:00"),
            ("2026-10-17T19:50:00+07:00", "2026-10-18T07:00:00+07:00"),
            ("2026-10-17T20:00:00+07:00", "2026-10-18T07:00:00+07:00"),
            ("2026-10-17T23:58:00+07:00", "2026-10-18T07:00:00+07:00")
        ] {
            let now = try date(start)
            let plan = try ReminderPlan(words: words, interval: 10, now: now, calendar: calendar)
            XCTAssertEqual(plan.dates.first, try date(expected), start)
            assertValid(plan, now: now, interval: 10, window: window, calendar: calendar)
        }
        XCTAssertTrue(window.contains(try date("2026-10-17T07:00:00+07:00"), calendar: calendar))
        XCTAssertTrue(window.contains(try date("2026-10-17T19:59:59+07:00"), calendar: calendar))
        XCTAssertFalse(window.contains(try date("2026-10-17T20:00:00+07:00"), calendar: calendar))
    }

    func testOvernightWindowAndMinutePrecision() throws {
        let calendar = try calendar()
        let window = ReminderTimeWindow(enabled: true, startMinute: 20 * 60 + 15, endMinute: 7 * 60 + 30)
        XCTAssertEqual(window.hoursSummary, "20:15 - 07:30")
        for (start, expected) in [
            ("2026-10-17T18:00:00+07:00", "2026-10-17T20:15:00+07:00"),
            ("2026-10-17T23:55:00+07:00", "2026-10-18T00:05:00+07:00"),
            ("2026-10-18T07:19:00+07:00", "2026-10-18T07:29:00+07:00"),
            ("2026-10-18T07:20:00+07:00", "2026-10-18T20:15:00+07:00")
        ] {
            let now = try date(start)
            let plan = try ReminderPlan(words: words, interval: 10, timeWindow: window, now: now, calendar: calendar)
            XCTAssertEqual(plan.dates.first, try date(expected))
            assertValid(plan, now: now, interval: 10, window: window, calendar: calendar)
        }
    }

    func testAllIntervalsAndShortWindowSpreadRequestsAcrossDaysWithoutBunching() throws {
        let calendar = try calendar()
        let window = ReminderTimeWindow(enabled: true, startMinute: 420, endMinute: 421)
        let now = try date("2026-12-31T20:00:00+07:00")
        for interval in ReminderPlan.intervals {
            let plan = try ReminderPlan(
                words: words, interval: interval, timeWindow: window, now: now, calendar: calendar
            )
            assertValid(plan, now: now, interval: interval, window: window, calendar: calendar)
            XCTAssertEqual(plan.dates.first, try date("2027-01-01T07:00:00+07:00"))
            XCTAssertEqual(plan.dates.last, try date("2027-02-19T07:00:00+07:00"))
        }
    }

    func testDisabledWindowPreservesUnrestrictedIntervalsAndEmptyListSchedulesNothing() throws {
        let now = try date("2026-10-17T23:58:00+07:00")
        let calendar = try calendar()
        let plan = try ReminderPlan(
            words: words, interval: 5, timeWindow: .unrestricted, now: now, calendar: calendar
        )
        XCTAssertEqual(plan.delays, (1...50).map { TimeInterval($0 * 300) })
        let empty = try ReminderPlan(words: [], interval: 1, now: now, calendar: calendar)
        XCTAssertTrue(empty.dates.isEmpty)
        XCTAssertTrue(empty.bodies.isEmpty)
    }

    func testMidnightWindowAndDifferentTimeZonesUseLocalHours() throws {
        let instant = try date("2026-10-17T18:00:00Z")
        let window = ReminderTimeWindow(enabled: true, startMinute: 22 * 60, endMinute: 0)
        for zone in ["Asia/Ho_Chi_Minh", "America/Los_Angeles", "Pacific/Auckland"] {
            let calendar = try calendar(zone)
            let plan = try ReminderPlan(words: words, interval: 60, timeWindow: window, now: instant, calendar: calendar)
            assertValid(plan, now: instant, interval: 60, window: window, calendar: calendar)
            XCTAssertTrue(plan.dates.allSatisfy {
                [22, 23].contains(calendar.component(.hour, from: $0))
            })
            let midnight = try XCTUnwrap(calendar.date(bySettingHour: 0, minute: 0, second: 0, of: instant))
            XCTAssertFalse(window.contains(midnight, calendar: calendar))
        }
    }

    func testSpringDSTSkippedOpeningAndEntirelySkippedWindow() throws {
        let calendar = try calendar("America/Los_Angeles")
        let now = try date("2026-03-08T01:00:00-08:00")
        let broad = ReminderTimeWindow(enabled: true, startMinute: 150, endMinute: 240)
        let broadPlan = try ReminderPlan(
            words: words, interval: 10, timeWindow: broad, now: now, calendar: calendar
        )
        XCTAssertEqual(broadPlan.dates.first, try date("2026-03-08T03:00:00-07:00"))
        assertValid(broadPlan, now: now, interval: 10, window: broad, calendar: calendar)
        let skipped = ReminderTimeWindow(enabled: true, startMinute: 130, endMinute: 140)
        let skippedPlan = try ReminderPlan(
            words: words, interval: 10, timeWindow: skipped, now: now, calendar: calendar
        )
        XCTAssertEqual(skippedPlan.dates.first, try date("2026-03-09T02:10:00-07:00"))
        assertValid(skippedPlan, now: now, interval: 10, window: skipped, calendar: calendar)
    }

    func testFallDSTAndLeapDayKeepEveryRequestInsideLocalWindow() throws {
        let calendar = try calendar("America/Los_Angeles")
        let now = try date("2026-11-01T00:30:00-07:00")
        let window = ReminderTimeWindow(enabled: true, startMinute: 90, endMinute: 105)
        let plan = try ReminderPlan(words: words, interval: 5, timeWindow: window, now: now, calendar: calendar)
        assertValid(plan, now: now, interval: 5, window: window, calendar: calendar)
        let leapNow = try date("2028-02-28T23:58:00-08:00")
        let leapPlan = try ReminderPlan(words: words, interval: 10, now: leapNow, calendar: calendar)
        XCTAssertEqual(leapPlan.dates.first, try date("2028-02-29T07:00:00-08:00"))
        assertValid(leapPlan, now: leapNow, interval: 10, window: .standard, calendar: calendar)
    }

    func testInvalidWindowsAreRejectedEvenWithEmptyListOrDisabledLimit() throws {
        for window in [
            ReminderTimeWindow(enabled: true, startMinute: -1, endMinute: 1200),
            ReminderTimeWindow(enabled: true, startMinute: 420, endMinute: 1440),
            ReminderTimeWindow(enabled: true, startMinute: 420, endMinute: 420),
            ReminderTimeWindow(enabled: false, startMinute: 0, endMinute: 0)
        ] {
            XCTAssertThrowsError(try window.validated())
            XCTAssertThrowsError(try ReminderPlan(words: [], interval: 10, timeWindow: window))
        }
    }

    func testCalendarTriggerUsesLocalWallTimeAndIsNotRepeating() throws {
        let calendar = try calendar()
        let target = try date("2027-01-01T07:15:30+07:00")
        let trigger = AppleReminderCenter.trigger(date: target, calendar: calendar)
        XCTAssertFalse(trigger.repeats)
        let components = trigger.dateComponents
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 15)
        XCTAssertEqual(components.second, 30)
        XCTAssertNil(components.timeZone)
        XCTAssertNil(components.calendar)
        let changedZone = try self.calendar("America/Los_Angeles")
        let localDate = try XCTUnwrap(changedZone.date(from: components))
        XCTAssertNotEqual(localDate, target)
        XCTAssertEqual(changedZone.component(.hour, from: localDate), 7)
        let local = ReminderTimeWindow.localCalendar
        let later = try XCTUnwrap(local.date(byAdding: .day, value: 2, to: Date()))
        let future = try XCTUnwrap(local.date(bySettingHour: 7, minute: 15, second: 30, of: later))
        XCTAssertEqual(AppleReminderCenter.trigger(date: future, calendar: local).nextTriggerDate(), future)
    }

    private func assertValid(
        _ plan: ReminderPlan, now: Date, interval: Int, window: ReminderTimeWindow, calendar: Calendar,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(plan.dates.count, 50, file: file, line: line)
        XCTAssertEqual(plan.bodies.count, 50, file: file, line: line)
        XCTAssertEqual(Set(plan.dates).count, 50, file: file, line: line)
        var previous = now
        for date in plan.dates {
            XCTAssertTrue(window.contains(date, calendar: calendar), "\(date)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(date.timeIntervalSince(previous), TimeInterval(interval * 60), file: file, line: line)
            previous = date
        }
    }
}
