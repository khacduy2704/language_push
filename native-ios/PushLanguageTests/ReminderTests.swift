import XCTest
@testable import PushLanguage

@MainActor
final class ReminderTests: XCTestCase {
    private actor Center: ReminderCenter {
        struct Request {
            let id: String
            let body: String
            let delay: TimeInterval
            let date: Date
            let calendar: Calendar
        }
        var authorization: ReminderPermission = .allowed
        var requests: [String: Request] = [:]
        var failAt: Int?
        var silentlyDrop = false
        var permissionError = false
        var requestCount = 0
        var removed: [String] = []

        func permission() async -> ReminderPermission { authorization }
        func requestPermission() async throws -> Bool {
            if permissionError { throw ReminderError.permissionDenied }
            return authorization == .allowed
        }
        func pendingIdentifiers() async -> [String] { Array(requests.keys) }
        func remove(identifiers: [String]) async {
            removed += identifiers
            for id in identifiers { requests.removeValue(forKey: id) }
            requestCount = 0
        }
        func add(id: String, body: String, date: Date, calendar: Calendar) async throws {
            requestCount += 1
            if requestCount == failAt { throw ReminderError.incompleteSchedule }
            if !silentlyDrop {
                requests[id] = Request(
                    id: id, body: body, delay: date.timeIntervalSinceNow, date: date, calendar: calendar
                )
            }
        }
        func configure(
            permission: ReminderPermission = .allowed, failAt: Int? = nil,
            silentlyDrop: Bool = false, permissionError: Bool = false
        ) {
            authorization = permission
            self.failAt = failAt
            self.silentlyDrop = silentlyDrop
            self.permissionError = permissionError
        }
        func seedOther(_ count: Int) {
            for index in 0..<count {
                requests["other-\(index)"] = Request(
                    id: "other-\(index)", body: "unrelated", delay: 100,
                    date: Date().addingTimeInterval(100), calendar: .current
                )
            }
        }
        func snapshot() -> [Request] { Array(requests.values) }
    }

    private func fixture() throws -> (WordStore, UserDefaults) {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "reminder-test-\(id)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(try JSONEncoder().encode(ReminderTimeWindow.unrestricted), forKey: ReminderTimeWindow.preferenceKey)
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        return (WordStore(databaseURL: directory.appendingPathComponent("words.db")), defaults)
    }

    func testPlanPreservesBodyFormattingAndFiftyFiniteIntervals() throws {
        let words = [
            SavedWord(id: 1, word: "Hello", partOfSpeech: "n", meaning: "A greeting", isPushed: true),
            SavedWord(id: 2, word: "Run", partOfSpeech: "v", meaning: "", isPushed: true)
        ]
        for interval in ReminderPlan.intervals {
            let plan = try ReminderPlan(words: words, interval: interval, timeWindow: .unrestricted)
            XCTAssertEqual(plan.bodies.count, 50)
            for body in plan.bodies {
                XCTAssertEqual(Set(body.components(separatedBy: "\n")), ["Hello (n) A greeting", "Run (v)"])
            }
            XCTAssertEqual(plan.delays.count, 50)
            XCTAssertEqual(plan.delays.first, Double(interval * 60))
            XCTAssertEqual(plan.delays.last, Double(interval * 60 * 50))
            XCTAssertEqual(Set(plan.delays).count, 50)
        }
        XCTAssertEqual(try ReminderPlan(words: [], interval: 10).delays, [])
        for invalid in [0, -1, 7] {
            XCTAssertThrowsError(try ReminderPlan(words: words, interval: invalid))
        }
        for invalid in [0, -1, 6] {
            XCTAssertThrowsError(try ReminderPlan(words: words, interval: 10, wordsPerReminder: invalid))
        }
    }

    func testUnlimitedMembershipPersistenceIdempotencyAndMissingWord() async throws {
        let (store, _) = try fixture()
        let words = try await store.words()
        for word in words { try await store.setPushed(id: word.id, pushed: true) }
        try await store.setPushed(id: words[0].id, pushed: true)
        var pushed = try await store.words().filter(\.isPushed)
        XCTAssertEqual(pushed.count, 9)
        let reopened = WordStore(databaseURL: try await store.location())
        let persisted = try await reopened.words().filter(\.isPushed)
        XCTAssertEqual(persisted, pushed)
        try await store.setPushed(id: words[0].id, pushed: false)
        try await store.setPushed(id: words[0].id, pushed: false)
        pushed = try await store.words().filter(\.isPushed)
        XCTAssertEqual(pushed.count, 8)
        let all = try await store.words()
        XCTAssertEqual(all.count, 9)
        do {
            try await store.setPushed(id: Int64.max, pushed: true)
            XCTFail("Missing membership target must fail.")
        } catch WordStorageError.missingWord {}
    }

    func testConcurrentPushAddsDoNotLimitMembership() async throws {
        let (store, _) = try fixture()
        let words = try await store.words()
        let successes = try await withThrowingTaskGroup(of: Bool.self) { group in
            for word in words {
                group.addTask {
                    try await store.setPushed(id: word.id, pushed: true)
                    return true
                }
            }
            var count = 0
            for try await result in group { if result { count += 1 } }
            return count
        }
        XCTAssertEqual(successes, words.count)
        let pushed = try await store.words().filter(\.isPushed)
        XCTAssertEqual(pushed.count, words.count)
    }

    func testRandomBatchesUseConfiguredCountWithoutRepeatsWithinEachNotification() throws {
        struct Generator: RandomNumberGenerator {
            var state: UInt64 = 42
            mutating func next() -> UInt64 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return state
            }
        }
        let words = (1...30).map {
            SavedWord(id: Int64($0), word: "Word \($0)", partOfSpeech: "n", meaning: "Meaning \($0)", isPushed: true)
        }
        for count in ReminderPlan.wordCounts {
            var generator = Generator()
            let plan = try ReminderPlan(words: words, interval: 5, wordsPerReminder: count, using: &generator)
            XCTAssertEqual(plan.batches.count, 50)
            XCTAssertEqual(plan.bodies.count, plan.delays.count)
            for (index, batch) in plan.batches.enumerated() {
                XCTAssertEqual(batch.count, count)
                XCTAssertEqual(Set(batch.map(\.id)).count, count)
                XCTAssertTrue(batch.allSatisfy { words.contains($0) })
                XCTAssertEqual(plan.bodies[index], batch.map {
                    "\($0.word) (\($0.partOfSpeech)) \($0.meaning)"
                }.joined(separator: "\n"))
            }
            let selected = Set(plan.batches.flatMap { $0.map(\.id) })
            XCTAssertGreaterThan(selected.count, 5)
            XCTAssertGreaterThan(Set(plan.batches.map { $0.map(\.id) }).count, 1)
            XCTAssertLessThan(selected.count, plan.batches.flatMap { $0 }.count)
            let small = try ReminderPlan(words: Array(words.prefix(2)), interval: 1, wordsPerReminder: count)
            XCTAssertTrue(small.batches.allSatisfy { $0.count == min(count, 2) })
            let empty = try ReminderPlan(words: [], interval: 1, wordsPerReminder: count)
            XCTAssertTrue(empty.batches.isEmpty)
            XCTAssertTrue(empty.bodies.isEmpty)
        }
    }

    func testWordCountPersistsRebuildsAllBodiesAndRejectsInvalidValues() async throws {
        let (store, defaults) = try fixture()
        for word in try await store.words() { try await store.setPushed(id: word.id, pushed: true) }
        let center = Center()
        await center.seedOther(1)
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        XCTAssertEqual(controller.wordsPerReminder, 5)
        for count in ReminderPlan.wordCounts {
            await controller.setWordsPerReminder(count)
            XCTAssertEqual(controller.words.count, 9)
            XCTAssertNil(controller.errorMessage)
            let requests = await center.snapshot()
            XCTAssertEqual(requests.count, 51)
            XCTAssertTrue(requests.filter { $0.id.hasPrefix(ReminderPlan.prefix) }.allSatisfy {
                $0.body.components(separatedBy: "\n").count == count
            })
            XCTAssertEqual(defaults.integer(forKey: "reminderWordsPerNotification"), count)
            let reopened = ReminderController(store: store, center: center, defaults: defaults)
            XCTAssertEqual(reopened.wordsPerReminder, count)
        }
        for invalid in [0, -1, 6] {
            await controller.setWordsPerReminder(invalid)
            XCTAssertEqual(controller.wordsPerReminder, 5)
            XCTAssertNotNil(controller.errorMessage)
            XCTAssertEqual(defaults.integer(forKey: "reminderWordsPerNotification"), 5)
        }
        for stored in [6, "invalid"] as [Any] {
            defaults.set(stored, forKey: "reminderWordsPerNotification")
            let invalid = ReminderController(store: store, center: center, defaults: defaults)
            await invalid.refresh()
            XCTAssertNotNil(invalid.errorMessage)
            let remaining = await center.snapshot()
            XCTAssertEqual(remaining.map(\.id), ["other-0"])
            await invalid.setWordsPerReminder(2)
            XCTAssertNil(invalid.errorMessage)
        }
    }

    func testSchedulingRebuildsEditedContentIntervalAndDeletesWithoutTouchingOtherNotifications() async throws {
        let (store, defaults) = try fixture()
        let words = try await store.words()
        let word = try XCTUnwrap(words.first)
        try await store.setPushed(id: word.id, pushed: true)
        let center = Center()
        await center.seedOther(1)
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        await controller.refresh()
        var requests = await center.snapshot()
        XCTAssertEqual(requests.count, 51)
        XCTAssertTrue(requests.filter { $0.id.hasPrefix(ReminderPlan.prefix) }.allSatisfy {
            $0.body == "\(word.word) (\(word.partOfSpeech)) \(word.meaning)"
        })
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.status, "50 reminders scheduled, every 10 min.")
        try await store.update(id: word.id, draft: WordDraft(word: "Edited", partOfSpeech: "v", meaning: "changed"))
        await controller.setInterval(1)
        requests = await center.snapshot()
        let first = try XCTUnwrap(requests.first { $0.id == ReminderPlan.prefix + "1" })
        XCTAssertEqual(first.body, "Edited (v) changed")
        XCTAssertGreaterThan(first.delay, 59)
        XCTAssertLessThanOrEqual(first.delay, 60)
        XCTAssertEqual(defaults.integer(forKey: "reminderIntervalMinutes"), 1)
        let reopened = ReminderController(store: store, center: center, defaults: defaults)
        XCTAssertEqual(reopened.interval, 1)
        try await store.delete(id: word.id)
        await controller.refresh()
        requests = await center.snapshot()
        XCTAssertEqual(requests.map(\.id), ["other-0"])
        XCTAssertTrue(controller.words.isEmpty)
    }

    func testMasteryRemovesWordFromAllPendingRemindersAndRelearningDoesNotReaddIt() async throws {
        let (store, defaults) = try fixture()
        let library = WordLibrary(store: store)
        let words = try await store.words()
        let first = try XCTUnwrap(words.first)
        let second = words[1]
        for word in [first, second] { try await library.setPushed(id: word.id, pushed: true) }
        let center = Center()
        await center.seedOther(1)
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        await controller.refresh()
        XCTAssertEqual(controller.words.count, 2)
        let before = library.revision
        for _ in 0..<5 { _ = try await library.recordPracticeAnswer(id: first.id, correct: true) }
        XCTAssertEqual(library.revision, before + 5)
        await controller.refresh()
        XCTAssertEqual(controller.words.map(\.id), [second.id])
        var requests = await center.snapshot()
        XCTAssertEqual(requests.count, 51)
        XCTAssertTrue(requests.filter { $0.id.hasPrefix(ReminderPlan.prefix) }.allSatisfy {
            !$0.body.contains(first.word) && $0.body.contains(second.word)
        })
        try await library.setMastered(id: second.id, mastered: true)
        await controller.refresh()
        XCTAssertTrue(controller.words.isEmpty)
        requests = await center.snapshot()
        XCTAssertEqual(requests.map(\.id), ["other-0"])
        try await library.setMastered(id: first.id, mastered: false)
        await controller.refresh()
        XCTAssertTrue(controller.words.isEmpty)
        let revision = library.revision
        do {
            _ = try await library.recordPracticeAnswer(id: second.id, correct: true)
            XCTFail("Mastered words must reject stale answers.")
        } catch WordStorageError.alreadyMastered {}
        XCTAssertEqual(library.revision, revision)
        try await library.setPushed(id: first.id, pushed: true)
        await controller.refresh()
        XCTAssertEqual(controller.words.map(\.id), [first.id])
    }

    func testDeniedAndUndeterminedPermissionsNeverScheduleAndKeepSelection() async throws {
        let (store, defaults) = try fixture()
        let words = try await store.words()
        try await store.setPushed(id: try XCTUnwrap(words.first?.id), pushed: true)
        let center = Center()
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        for permission in [ReminderPermission.notDetermined, .denied] {
            await center.configure(permission: permission)
            await controller.refresh()
            let requests = await center.snapshot()
            XCTAssertTrue(requests.isEmpty)
            XCTAssertEqual(controller.words.count, 1)
        }
        await controller.enable()
        XCTAssertNotNil(controller.errorMessage)
        await center.configure(permissionError: true)
        await controller.enable()
        XCTAssertNotNil(controller.errorMessage)
        await center.configure()
        await controller.enable()
        XCTAssertNil(controller.errorMessage)
        let scheduled = await center.snapshot()
        XCTAssertEqual(scheduled.count, 50)
    }

    func testPermissionReminderChecksEmptyListAndUpdatesAfterPermissionChanges() async throws {
        let (store, defaults) = try fixture()
        let center = Center()
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        XCTAssertFalse(controller.hasCheckedPermission)
        XCTAssertFalse(controller.needsPermissionReminder)
        for permission in [ReminderPermission.notDetermined, .denied, .allowed, .denied] {
            await center.configure(permission: permission)
            await controller.refresh()
            XCTAssertTrue(controller.hasCheckedPermission)
            XCTAssertTrue(controller.words.isEmpty)
            XCTAssertEqual(controller.permission, permission)
            XCTAssertEqual(controller.needsPermissionReminder, permission != .allowed)
            XCTAssertEqual(controller.status, "No words selected for push yet.")
        }
        await controller.enable()
        XCTAssertTrue(controller.needsPermissionReminder)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isRequestingPermission)
        await center.configure()
        await controller.enable()
        XCTAssertFalse(controller.needsPermissionReminder)
        XCTAssertNil(controller.errorMessage)
        XCTAssertFalse(controller.isRequestingPermission)
        let requests = await center.snapshot()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDailyWindowDefaultsPersistenceReschedulingAndInvalidPreferenceRepair() async throws {
        let (store, defaults) = try fixture()
        defaults.removeObject(forKey: ReminderTimeWindow.preferenceKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-17T21:00:00+07:00"))
        for word in try await store.words() { try await store.setPushed(id: word.id, pushed: true) }
        let center = Center()
        await center.seedOther(1)
        let controller = ReminderController(
            store: store, center: center, defaults: defaults, now: { now }, calendar: { calendar }
        )
        XCTAssertEqual(controller.timeWindow, .standard)
        await controller.refresh()
        var requests = await center.snapshot().filter { $0.id.hasPrefix(ReminderPlan.prefix) }
        XCTAssertEqual(requests.count, 50)
        XCTAssertTrue(requests.allSatisfy { controller.timeWindow.contains($0.date, calendar: calendar) })
        XCTAssertTrue(requests.allSatisfy { $0.body.components(separatedBy: "\n").count == 5 })
        XCTAssertEqual(requests.first { $0.id == ReminderPlan.prefix + "1" }?.date,
                       ISO8601DateFormatter().date(from: "2026-10-18T07:00:00+07:00"))
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        await controller.refresh()
        requests = await center.snapshot().filter { $0.id.hasPrefix(ReminderPlan.prefix) }
        XCTAssertTrue(requests.allSatisfy { controller.timeWindow.contains($0.date, calendar: calendar) })
        XCTAssertEqual(requests.first { $0.id == ReminderPlan.prefix + "1" }?.date, now.addingTimeInterval(600))
        let overnight = ReminderTimeWindow(enabled: true, startMinute: 1215, endMinute: 450)
        let saved = await controller.setTimeWindow(overnight)
        XCTAssertTrue(saved)
        XCTAssertEqual(try ReminderTimeWindow.load(from: defaults), overnight)
        let reopened = ReminderController(store: store, center: center, defaults: defaults)
        XCTAssertEqual(reopened.timeWindow, overnight)
        requests = await center.snapshot().filter { $0.id.hasPrefix(ReminderPlan.prefix) }
        XCTAssertTrue(requests.allSatisfy { overnight.contains($0.date, calendar: calendar) })
        let invalid = await controller.setTimeWindow(
            ReminderTimeWindow(enabled: true, startMinute: 100, endMinute: 100)
        )
        XCTAssertFalse(invalid)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(controller.timeWindow, overnight)
        XCTAssertEqual(try ReminderTimeWindow.load(from: defaults), overnight)
        let allDay = await controller.setTimeWindow(.unrestricted)
        XCTAssertTrue(allDay)
        requests = await center.snapshot().filter { $0.id.hasPrefix(ReminderPlan.prefix) }
        XCTAssertEqual(requests.first { $0.id == ReminderPlan.prefix + "1" }?.date, now.addingTimeInterval(600))
        for corrupt in [Data("{}".utf8), "invalid", try JSONEncoder().encode(
            ReminderTimeWindow(enabled: true, startMinute: 1440, endMinute: 0)
        )] as [Any] {
            defaults.set(corrupt, forKey: ReminderTimeWindow.preferenceKey)
            let broken = ReminderController(store: store, center: center, defaults: defaults)
            await broken.refresh()
            XCTAssertNotNil(broken.errorMessage)
            let remaining = await center.snapshot()
            XCTAssertEqual(remaining.map(\.id), ["other-0"])
            XCTAssertEqual(broken.words.count, 9)
            let repaired = await broken.setTimeWindow(.standard)
            XCTAssertTrue(repaired)
            XCTAssertNil(broken.errorMessage)
        }
    }

    func testPartialFailureAndSilentDropsCancelAllOwnedRequestsAndRetry() async throws {
        let (store, defaults) = try fixture()
        let words = try await store.words()
        try await store.setPushed(id: try XCTUnwrap(words.first?.id), pushed: true)
        let center = Center()
        await center.seedOther(1)
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        for silentlyDrop in [false, true] {
            await center.configure(failAt: silentlyDrop ? nil : 20, silentlyDrop: silentlyDrop)
            await controller.refresh()
            XCTAssertNotNil(controller.errorMessage)
            let remaining = await center.snapshot()
            XCTAssertEqual(remaining.map(\.id), ["other-0"])
            XCTAssertEqual(controller.words.count, 1)
        }
        await center.configure()
        await controller.refresh()
        XCTAssertNil(controller.errorMessage)
        let requests = await center.snapshot()
        XCTAssertEqual(requests.count, 51)
    }

    func testCapacityAndInvalidPreferencesAreExplicitAndNonDestructive() async throws {
        let (store, defaults) = try fixture()
        let words = try await store.words()
        try await store.setPushed(id: try XCTUnwrap(words.first?.id), pushed: true)
        let center = Center()
        await center.seedOther(15)
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        await controller.refresh()
        XCTAssertTrue(try XCTUnwrap(controller.errorMessage).contains("insufficient capacity"))
        let requests = await center.snapshot()
        XCTAssertEqual(requests.count, 15)
        await controller.setInterval(0)
        XCTAssertEqual(controller.interval, 10)
        XCTAssertNotNil(controller.errorMessage)
        defaults.set(-1, forKey: "reminderIntervalMinutes")
        let invalid = ReminderController(store: store, center: center, defaults: defaults)
        await invalid.refresh()
        XCTAssertTrue(try XCTUnwrap(invalid.errorMessage).contains("supported reminder interval"))
    }

    func testConcurrentRefreshesEndWithNewestDatabaseContent() async throws {
        let (store, defaults) = try fixture()
        let words = try await store.words()
        let id = try XCTUnwrap(words.first?.id)
        try await store.setPushed(id: id, pushed: true)
        let center = Center()
        let controller = ReminderController(store: store, center: center, defaults: defaults)
        let first = Task { await controller.refresh() }
        try await store.update(id: id, draft: WordDraft(word: "Latest", partOfSpeech: "n", meaning: "latest"))
        let second = Task { await controller.refresh() }
        await first.value
        await second.value
        let requests = await center.snapshot()
        XCTAssertEqual(requests.count, 50)
        XCTAssertTrue(requests.allSatisfy { $0.body == "Latest (n) latest" })
    }
}
