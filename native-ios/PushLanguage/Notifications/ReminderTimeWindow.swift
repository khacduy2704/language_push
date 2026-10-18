import Foundation

struct ReminderTimeWindow: Codable, Equatable {
    static let preferenceKey = "reminderTimeWindow"
    static let standard = ReminderTimeWindow(enabled: true, startMinute: 7 * 60, endMinute: 20 * 60)
    static let unrestricted = ReminderTimeWindow(enabled: false, startMinute: 7 * 60, endMinute: 20 * 60)

    var enabled: Bool
    var startMinute: Int
    var endMinute: Int

    var hoursSummary: String {
        String(format: "%02d:%02d - %02d:%02d", startMinute / 60, startMinute % 60, endMinute / 60, endMinute % 60)
    }

    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    func validated() throws -> Self {
        guard (0..<1440).contains(startMinute), (0..<1440).contains(endMinute),
              startMinute != endMinute else { throw ReminderError.invalidTimeWindow }
        return self
    }

    static func load(from defaults: UserDefaults) throws -> Self {
        guard let stored = defaults.object(forKey: preferenceKey) else { return .standard }
        guard let data = stored as? Data else { throw ReminderError.invalidTimeWindow }
        do {
            return try JSONDecoder().decode(Self.self, from: data).validated()
        } catch is DecodingError {
            throw ReminderError.invalidTimeWindow
        }
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard enabled else { return true }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    func nextAllowedDate(onOrAfter date: Date, calendar: Calendar) throws -> Date {
        if contains(date, calendar: calendar) { return date }
        var cursor = date
        let opening = DateComponents(hour: startMinute / 60, minute: startMinute % 60, second: 0)
        // A DST jump can skip the entire window; search the following day instead.
        for _ in 0..<8 {
            guard let next = calendar.nextDate(
                after: cursor, matching: opening, matchingPolicy: .nextTime,
                repeatedTimePolicy: .first, direction: .forward
            ) else { throw ReminderError.invalidScheduleDate }
            if contains(next, calendar: calendar) { return next }
            cursor = next
        }
        throw ReminderError.invalidScheduleDate
    }
}
