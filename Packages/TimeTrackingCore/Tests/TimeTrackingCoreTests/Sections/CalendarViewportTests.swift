// Tests of the Calendar's strip of days: sideways scrolling, the arrows'
// snapping, and the day width (calendar.md §1.2, §7).

import Foundation
import Testing
import TimeTrackingCore

@Suite("Calendar viewport")
struct CalendarViewportTests {
    @Test("PC-3 a sideways scroll of 1.4 day widths moves 1.4 days; the arrows then snap a day start to the left edge")
    func sidewaysScroll() {
        let monday = TrackingDay(year: 2026, month: 10, day: 26)
        var viewport = CalendarViewport(firstDay: monday, dayWidth: 200, width: 1000)
        viewport.scroll(byPoints: 280)
        #expect(viewport.firstDay == monday.adding(days: 1))
        #expect(abs(viewport.offset - 0.4) < 1e-9)
        #expect(abs(viewport.x(of: monday.adding(days: 2)) - 120) < 1e-9)
        // Six days have a part in view; the subtitle counts the five at
        // least half visible (60% of the first, 40% of the last show).
        #expect(viewport.touchedDays == (1 ... 6).map { monday.adding(days: $0) })
        #expect(viewport.shownDays == (1 ... 5).map { monday.adding(days: $0) })
        // → goes to the next day boundary, ← from a cut-off day to its start.
        var next = viewport
        next.step(days: 1)
        #expect(next.firstDay == monday.adding(days: 2))
        #expect(next.offset == 0)
        var back = viewport
        back.step(days: -1)
        #expect(back.firstDay == monday.adding(days: 1))
        #expect(back.offset == 0)
        back.step(days: -1)
        #expect(back.firstDay == monday)
        back.step(days: -5)
        #expect(back.firstDay == monday.adding(days: -5))
        // Back across a day boundary.
        viewport.scroll(byPoints: -460)
        #expect(viewport.firstDay == monday.adding(days: -1))
        #expect(abs(viewport.offset - 0.1) < 1e-9)
    }

    @Test(
        "PC-27 the window's width decides how many days of the day width show; the slider is logarithmic; zooming keeps the center"
    )
    func dayWidth() {
        let monday = TrackingDay(year: 2026, month: 10, day: 26)
        var viewport = CalendarViewport(firstDay: monday, dayWidth: 250, width: 1000)
        #expect(viewport.wholeDays == 4)
        #expect(viewport.touchedDays.count == 4)
        viewport.setWidth(1100)
        #expect(viewport.wholeDays == 4)
        #expect(viewport.touchedDays.count == 5)
        #expect(viewport.firstDay == monday)
        // The time at the center stays put.
        let center = { (viewport: CalendarViewport) in
            Double(monday.distance(to: viewport.firstDay)) + viewport.offset + viewport.span / 2
        }
        let before = center(viewport)
        viewport.setDayWidth(500)
        #expect(abs(center(viewport) - before) < 1e-9)
        #expect(viewport.wholeDays == 2)
        viewport.setDayWidth(10)
        #expect(viewport.dayWidth == CalendarViewport.dayWidthRange.lowerBound)
        viewport.setDayWidth(10_000)
        #expect(viewport.dayWidth == CalendarViewport.dayWidthRange.upperBound)
        #expect(viewport.shownDays.count == 1)
        // ⌥-click: one day as wide as the viewport.
        viewport.showAlone(monday)
        #expect(viewport.dayWidth == 1100)
        #expect(viewport.touchedDays == [monday])
        #expect(CalendarViewport.sliderValue(dayWidth: CalendarViewport.dayWidthRange.lowerBound) == 0)
        #expect(abs(CalendarViewport.sliderValue(dayWidth: CalendarViewport.dayWidthRange.upperBound) - 1) < 1e-12)
        #expect(abs(CalendarViewport.dayWidth(sliderValue: CalendarViewport.sliderValue(dayWidth: 260)) - 260) < 1e-9)
        #expect(abs(CalendarViewport.dayWidth(sliderValue: 0.5) - (96 * 1600).squareRoot()) < 1e-9)
        // Saturdays and Sundays are shaded.
        #expect((0 ..< 7).map { monday.adding(days: $0).isWeekend } == [false, false, false, false, false, true, true])
    }
}
