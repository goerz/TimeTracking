// The Activity section's drill-down from a bar segment and its keyboard
// focus on the heatmap and the bars (activity.md §2, §3).

import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct ActivityKeyboardTests {
    @Test("PA-26 clicking a segment opens the Calendar at its day with its app highlighted; above the stack nothing is")
    func segmentDrill() async throws {
        let test = try await TestApp()
        let (router, _) = try ActivitySectionTests.router(test, blocks: ActivitySectionTests.week())
        let model = router.activity
        await model.reload()
        let bars = try #require(model.summary?.bars)
        let monday = try #require(bars.bars.first)
        let day = TrackingDay(year: 2024, month: 3, day: 11)
        model.showInCalendar(ActivityBars.Target(bar: monday.id, series: monday.series(atSeconds: 2000)), in: bars)
        #expect(router.calendarRequest == CalendarRequest(day: day, hour: nil, highlight: .app("Safari")))
        model.showInCalendar(ActivityBars.Target(bar: monday.id, series: monday.series(atSeconds: 9000)), in: bars)
        #expect(router.calendarRequest == CalendarRequest(day: day, hour: nil, highlight: nil))
    }

    @Test("PA-27 the heatmap's keys start on the first cell and Return opens the focused cell's day and hour")
    func heatmapKeys() async throws {
        let test = try await TestApp()
        let (router, _) = try ActivitySectionTests.router(test, blocks: ActivitySectionTests.week())
        let model = router.activity
        await model.reload()
        model.heatmapFocused()
        #expect(model.focusedCell == ActivityHeatmap.Cell(row: "day:2024-03-11", hour: 0))
        model.moveFocusedCell(.right)
        model.moveFocusedCell(.below)
        model.heatmapFocused()
        #expect(model.focusedCell == ActivityHeatmap.Cell(row: "day:2024-03-12", hour: 1))
        model.openFocusedCell()
        #expect(router.calendarRequest == CalendarRequest(day: TrackingDay(year: 2024, month: 3, day: 12), hour: 1, highlight: .hour(1)))
    }

    @Test("PA-28 the chart's keys start on the first bar and Return opens the focused bar or segment like a click")
    func barKeys() async throws {
        let test = try await TestApp()
        let (router, _) = try ActivitySectionTests.router(test, blocks: ActivitySectionTests.week())
        let model = router.activity
        await model.reload()
        model.barsFocused()
        let monday = TrackingDay(year: 2024, month: 3, day: 11)
        #expect(model.focusedBar?.bar == monday.description)
        model.openFocusedBar()
        #expect(router.calendarRequest == CalendarRequest(day: monday, hour: nil, highlight: nil))
        model.moveFocusedBar(.above)
        model.openFocusedBar()
        #expect(router.calendarRequest == CalendarRequest(day: monday, hour: nil, highlight: .app("WezTerm")))
    }
}
