// Tests for Clock and ManualClock (spec_architecture.md §3.3).

import Foundation
import Testing
import TimeTrackingCore

struct ClockTests {
    @Test func manualClockMovesOnlyWhenTold() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = ManualClock(start)
        #expect(clock.now == start)
        clock.advance(by: 90)
        #expect(clock.now == start + 90)
        clock.set(start - 10)
        #expect(clock.now == start - 10)
    }

    @Test func fixtureNowIsTenOClockLocalOnMarch14() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: ManualClock.fixtureNow(in: zone))
        #expect(parts.year == 2024)
        #expect(parts.month == 3)
        #expect(parts.day == 14)
        #expect(parts.hour == 10)
        #expect(parts.minute == 0)
        #expect(parts.weekday == 5)
    }

    @Test func systemClockFollowsTheWallClock() {
        let before = Date()
        let now = SystemClock().now
        #expect(now >= before)
    }
}
