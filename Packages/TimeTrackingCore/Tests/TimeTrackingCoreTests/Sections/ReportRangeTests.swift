// Date ranges, presets, arrows, labels, granularity (reports.md §2, §4.3).

import Foundation
import Testing
import TimeTrackingCore

struct ReportRangeTests {
    /// Thursday, October 29, 2026.
    let today = TrackingDay(year: 2026, month: 10, day: 29)

    func day(_ text: String) throws -> TrackingDay {
        try #require(TrackingDay(text))
    }

    func days(_ range: ReportRange) -> String {
        let days = range.days(today: today, earliest: TrackingDay(year: 2019, month: 3, day: 4))
        return "\(days.lowerBound) \(days.upperBound)"
    }

    @Test func presetsAndLabels() {
        let earliest = TrackingDay(year: 2019, month: 3, day: 4)
        let expected: [RangePreset: [String]] = [
            .today: ["2026-10-29 2026-10-29", "Today · Thu 10/29"],
            .yesterday: ["2026-10-28 2026-10-28", "Yesterday · Wed 10/28"],
            .thisWeek: ["2026-10-26 2026-11-01", "This week · W44"],
            .lastWeek: ["2026-10-19 2026-10-25", "Last week · W43"],
            .thisMonth: ["2026-10-01 2026-10-31", "This month · October 2026"],
            .lastMonth: ["2026-09-01 2026-09-30", "Last month · September 2026"],
            .thisYear: ["2026-01-01 2026-12-31", "This year · 2026"],
            .lastYear: ["2025-01-01 2025-12-31", "Last year · 2025"],
            .weekToDate: ["2026-10-26 2026-10-29", "Week to date · W44"],
            .monthToDate: ["2026-10-01 2026-10-29", "Month to date · October 2026"],
            .last7Days: ["2026-10-23 2026-10-29", "Last 7 days · Oct 23 – 29"],
            .last30Days: ["2026-09-30 2026-10-29", "Last 30 days · Sep 30 – Oct 29"],
            .allTime: ["2019-03-04 2026-10-29", "All time · since Mar 4, 2019"],
        ]
        for (preset, texts) in expected {
            let (range, label) = (texts[0], texts[1])
            #expect(days(.preset(preset)) == range, "\(preset)")
            #expect(ReportRange.preset(preset).label(today: today, earliest: earliest) == label)
        }
        #expect(ReportRange.preset(.allTime).days(today: today, earliest: nil) == today ... today)
        let custom = ReportRange.days(TrackingDay(year: 2026, month: 11, day: 1), TrackingDay(year: 2026, month: 10, day: 19))
        #expect(custom.label(today: today, earliest: nil) == "Oct 19 – Nov 1, 2026")
    }

    @Test("PR-8 the arrows shift by the range's own unit; Week to date goes to the full previous week; All time disables both")
    func arrows() throws {
        let weekToDate = try #require(ReportRange.preset(.weekToDate).shifted(by: -1, today: today))
        #expect(days(weekToDate) == "2026-10-19 2026-10-25")
        #expect(weekToDate.label(today: today, earliest: nil) == "Week 43 · Oct 19 – 25")
        let month = try #require(ReportRange.preset(.thisMonth).shifted(by: -1, today: today)?.shifted(by: -1, today: today))
        #expect(days(month) == "2026-08-01 2026-08-31")
        #expect(month.label(today: today, earliest: nil) == "August 2026")
        let monthToDate = try #require(ReportRange.preset(.monthToDate).shifted(by: 1, today: today))
        #expect(days(monthToDate) == "2026-11-01 2026-11-30")
        let last7 = try #require(ReportRange.preset(.last7Days).shifted(by: -1, today: today))
        #expect(days(last7) == "2026-10-16 2026-10-22")
        let year = try #require(ReportRange.preset(.thisYear).shifted(by: -1, today: today))
        #expect(year.label(today: today, earliest: nil) == "2025")
        let single = try #require(ReportRange.preset(.today).shifted(by: 1, today: today))
        #expect(days(single) == "2026-10-30 2026-10-30")
        let custom = try ReportRange.days(day("2026-10-05"), day("2026-10-18"))
        #expect(try days(#require(custom.shifted(by: 1, today: today))) == "2026-10-19 2026-11-01")
        #expect(custom.label(today: today, earliest: nil) == "Oct 5 – 18, 2026")
        #expect(ReportRange.preset(.allTime).shifted(by: -1, today: today) == nil)
        #expect(ReportRange.preset(.allTime).shifted(by: 1, today: today) == nil)
        #expect(!ReportRange.preset(.allTime).canShift)
    }

    @Test(
        "PR-9 Go to Today: a shifted week becomes This week, a custom 10-day range the 10 days ending today; presets highlight on equality"
    )
    func goToToday() throws {
        let shifted = try #require(ReportRange.preset(.thisWeek).shifted(by: -3, today: today))
        #expect(shifted.goingToToday(today: today) == .preset(.thisWeek))
        #expect(shifted.matchingPresets(today: today, earliest: nil).isEmpty)
        let back = try #require(shifted.shifted(by: 2, today: today))
        #expect(back.matchingPresets(today: today, earliest: nil) == [.lastWeek])
        let tenDays = try ReportRange.days(day("2026-09-01"), day("2026-09-10"))
        #expect(days(tenDays.goingToToday(today: today)) == "2026-10-20 2026-10-29")
        let sevenDays = try ReportRange.days(day("2026-09-02"), day("2026-09-08"))
        #expect(sevenDays.goingToToday(today: today).matchingPresets(today: today, earliest: nil) == [.last7Days])
        #expect(ReportRange.preset(.thisMonth).shifted(by: -1, today: today)?.goingToToday(today: today) == .preset(.thisMonth))
    }

    @Test("PR-9 the range menu's title is the preset's name exactly when the range equals a preset, else the range by kind")
    func menuTitle() throws {
        func title(_ range: ReportRange?) -> String? {
            range?.menuTitle(today: today, earliest: nil)
        }
        #expect(title(.preset(.thisMonth)) == "This month")
        let week = ReportRange.preset(.thisWeek)
        #expect(title(week.shifted(by: -1, today: today)) == "Last week")
        #expect(title(week.shifted(by: -3, today: today)) == "Week 41")
        #expect(title(week.shifted(by: -3, today: today)?.shifted(by: 3, today: today)) == "This week")
        #expect(title(ReportRange.preset(.thisMonth).shifted(by: -2, today: today)) == "August 2026")
        #expect(title(ReportRange.preset(.thisYear).shifted(by: -2, today: today)) == "2024")
        #expect(title(ReportRange.preset(.today).shifted(by: -2, today: today)) == "Tue 10/27")
        #expect(try title(ReportRange.days(day("2026-10-05"), day("2026-10-18"))) == "Oct 5 – 18")
    }

    @Test("PR-10 a stored This week restored in a later week shows the later week")
    func storedRange() throws {
        let data = try JSONEncoder().encode(ReportRange.preset(.thisWeek))
        let restored = try JSONDecoder().decode(ReportRange.self, from: data)
        let later = TrackingDay(year: 2026, month: 11, day: 12)
        #expect(restored.days(today: later, earliest: nil) == TrackingDay(year: 2026, month: 11, day: 9) ... TrackingDay(
            year: 2026,
            month: 11,
            day: 15
        ))
        let custom = try ReportRange.days(day("2026-10-05"), day("2026-10-18"))
        let restoredCustom = try JSONDecoder().decode(ReportRange.self, from: JSONEncoder().encode(custom))
        #expect(restoredCustom == custom)
        let long = try ReportRange.days(day("2024-01-01"), day("2026-10-29"))
        let capped = long.capped(to: 366, today: today, earliest: nil)
        #expect(capped.clipped)
        #expect(capped.days.lowerBound.distance(to: capped.days.upperBound) == 365)
    }

    @Test("PR-2 Automatic granularity is Day to 31 days, Week to 182, Month to 1,096, Year beyond; weeks run Monday to Sunday")
    func automaticGranularity() {
        #expect(Granularity.automatic(dayCount: 1) == .day)
        #expect(Granularity.automatic(dayCount: 31) == .day)
        #expect(Granularity.automatic(dayCount: 32) == .week)
        #expect(Granularity.automatic(dayCount: 182) == .week)
        #expect(Granularity.automatic(dayCount: 183) == .month)
        #expect(Granularity.automatic(dayCount: 1096) == .month)
        #expect(Granularity.automatic(dayCount: 1097) == .year)
        let week = TrackingPeriod(.week, containing: today)
        #expect(week.start == TrackingDay(year: 2026, month: 10, day: 26))
        #expect(week.nextStart == TrackingDay(year: 2026, month: 11, day: 2))
    }
}
