// ReminderSchedule: when "Nothing is being tracked" reminders fire
// (spec_timer_window.md §7).

public import Foundation

/// The reminder settings (device) and the next fire time.
public struct ReminderSchedule: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    /// Minutes between reminders, 1 to 240.
    public var everyMinutes: Int
    /// Minutes after midnight; the window is `[start, end)`.
    public var startMinute: Int
    public var endMinute: Int
    /// ISO weekdays, 1 (Monday) to 7 (Sunday).
    public var weekdays: Set<Int>
    /// Minutes, 5 to 480.
    public var snoozeMinutes: Int

    public init(
        isEnabled: Bool = false,
        everyMinutes: Int = 10,
        startMinute: Int = 9 * 60,
        endMinute: Int = 17 * 60,
        weekdays: Set<Int> = [1, 2, 3, 4, 5],
        snoozeMinutes: Int = 60
    ) {
        self.isEnabled = isEnabled
        self.everyMinutes = everyMinutes
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.weekdays = weekdays
        self.snoozeMinutes = snoozeMinutes
    }

    /// The interval between reminders in seconds.
    public var interval: TimeInterval {
        TimeInterval(min(max(everyMinutes, 1), 240) * 60)
    }

    /// The snooze duration in seconds.
    public var snoozeInterval: TimeInterval {
        TimeInterval(min(max(snoozeMinutes, 5), 480) * 60)
    }

    /// Whether `date` lies inside the hours on a selected day.
    public func isInsideWindow(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let isoWeekday = ((parts.weekday ?? 1) + 5) % 7 + 1
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return weekdays.contains(isoWeekday) && minute >= startMinute && minute < endMinute
    }

    /// The next reminder while idle: `interval` after `anchor` (the last
    /// stop or reminder), not before `snoozedUntil`, moved to the next
    /// window start when it falls outside the hours; `nil` when off or no
    /// day is selected.
    public func nextFire(after anchor: Date, snoozedUntil: Date?, calendar: Calendar) -> Date? {
        guard isEnabled, !weekdays.isEmpty, startMinute < endMinute else {
            return nil
        }
        var candidate = anchor + interval
        if let snoozedUntil, snoozedUntil > candidate {
            candidate = snoozedUntil
        }
        if isInsideWindow(candidate, calendar: calendar) {
            return candidate
        }
        // The next window start at or after the candidate, within two weeks.
        var day = calendar.startOfDay(for: candidate)
        for _ in 0 ..< 15 {
            let start = calendar.date(byAdding: .minute, value: startMinute, to: day) ?? day
            if start >= candidate, isInsideWindow(start, calendar: calendar) {
                return start
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }
            day = next
        }
        return nil
    }

    /// Whether a reminder is due at `now`: inside the hours and past
    /// `nextFire`. The owner checks that nothing runs and the Mac is unlocked.
    public func isDue(at now: Date, anchor: Date, snoozedUntil: Date?, calendar: Calendar) -> Bool {
        guard isInsideWindow(now, calendar: calendar),
              let fire = nextFire(after: anchor, snoozedUntil: snoozedUntil, calendar: calendar)
        else {
            return false
        }
        return now >= fire
    }
}
