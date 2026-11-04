// Tests of the sleep and workout labels in the Calendar's Activity column
// (spec_calendar.md §3.1, §7).

import Foundation
import Testing
import TimeTrackingCore

@Suite("Calendar health labels")
struct CalendarHealthLabelTests {
    @Test("PC-29 a night from 23:00 to 06:30 is labeled 7h 30m on the day it ends; a workout on its own day")
    func labelDay() throws {
        let zone = TestTime.newYork
        let calendar = TrackingCalendar(timeZone: zone)
        let now = try TestTime.local("2026-10-30T12:00", in: zone)
        let night = try HealthPeriod(
            kind: .sleep,
            start: TestTime.local("2026-10-29T23:00", in: zone),
            end: TestTime.local("2026-10-30T06:30", in: zone),
            createdAt: now,
            modifiedAt: now
        )
        #expect(night.labelDay(in: calendar) == TrackingDay(year: 2026, month: 10, day: 30))
        #expect(night.durationText == "7h 30m")
        let toMidnight = try HealthPeriod(
            kind: .workout,
            start: TestTime.local("2026-10-29T23:15", in: zone),
            end: TestTime.local("2026-10-30T00:00", in: zone),
            createdAt: now,
            modifiedAt: now
        )
        #expect(toMidnight.labelDay(in: calendar) == TrackingDay(year: 2026, month: 10, day: 29))
        #expect(toMidnight.durationText == "45m")
    }
}
