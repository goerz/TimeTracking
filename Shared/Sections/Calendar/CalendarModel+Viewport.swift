// The Calendar's strip of days: the days it shows and their labels,
// sideways scrolling, the day width, and loading the data around the days
// in view (calendar.md §1.1, §1.2).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// The leftmost day, possibly cut off.
    var firstDay: TrackingDay {
        viewport.firstDay
    }

    /// The days the strip draws: those in the viewport and one more on each
    /// side, so a day sliding out of view stays drawn while it moves.
    var drawnDays: [TrackingDay] {
        guard let first = days.first, let last = days.last else {
            return []
        }
        return [first.adding(days: -1)] + days + [last.adding(days: 1)]
    }

    var visibleInterval: DateInterval {
        calendar.interval(of: days[0] ... days[days.count - 1])
    }

    /// "Mon, Oct 26 – Fri, Oct 30 · W44" for the shown days.
    var rangeLabel: String {
        CalendarStrip.label(first: shownDays[0], count: shownDays.count)
    }

    /// The date menu's title: "Today" while today is shown, else "Oct 19 – 23".
    var menuTitle: String {
        CalendarStrip.menuTitle(first: shownDays[0], count: shownDays.count, today: today)
    }

    /// A sideways trackpad or mouse scroll by `points`, without snapping;
    /// `momentum` for a trackpad's coasting after the fingers lift, which
    /// stops once the arrows or a header click have moved the days.
    func scroll(byPoints points: Double, momentum: Bool = false) {
        if !momentum {
            ignoresMomentum = false
        }
        guard points != 0, !(momentum && ignoresMomentum) else {
            return
        }
        centersTodayOnLayout = false
        viewport.scroll(byPoints: points)
    }

    /// The window's width for the days; the first one centers today.
    func setViewportWidth(_ width: Double) {
        guard abs(width - viewport.width) >= 0.5 else {
            return
        }
        viewport.setWidth(width)
        if centersTodayOnLayout, width > 0 {
            centersTodayOnLayout = false
            viewport.center(today)
        }
    }

    /// The day width slider, ⌥⌘[ / ⌥⌘], and a horizontal pinch; the time at
    /// `anchor` (the viewport's center when nil) stays in place.
    func setDayWidth(_ width: Double, anchor: Double? = nil) {
        viewport.setDayWidth(width, anchor: anchor)
    }

    /// ⌥⌘] (`step` 1) and ⌥⌘[ (-1).
    func zoomDays(by step: Int) {
        let factor = step > 0 ? CalendarViewport.dayWidthStep : 1 / CalendarViewport.dayWidthStep
        setDayWidth(dayWidth * factor)
    }

    /// Keeps the derived values and the loaded data in step with the
    /// viewport, assigning only what changed.
    func viewportChanged() {
        if dayWidth != viewport.dayWidth {
            dayWidth = viewport.dayWidth
            device[.calendarDayWidth] = dayWidth
        }
        let touched = viewport.touchedDays
        if touched != days {
            days = touched
        }
        let shown = viewport.shownDays
        if shown != shownDays {
            shownDays = shown
            refreshSummary()
        }
        if !coversDays {
            scheduleLoad()
        }
    }

    /// Whether the loaded data covers the days in view.
    var coversDays: Bool {
        guard let loadedDays, let first = days.first, let last = days.last else {
            return false
        }
        return loadedDays.contains(first) && loadedDays.contains(last)
    }

    /// Loads once the running load is done, unless that one covered the days.
    func scheduleLoad() {
        let previous = loadTask
        loadTask = Task {
            await previous?.value
            if !coversDays {
                await reload()
            }
        }
    }

    /// Waits for the scheduled loads.
    func loaded() async {
        await loadTask?.value
    }

    /// The summary strip over the shown days and the headers' totals over
    /// the loaded days, from the loaded data.
    func refreshTotals() {
        if let loadedDays {
            let span = loadedDays.lowerBound.distance(to: loadedDays.upperBound)
            dayTotals = summarize((0 ... span).map { loadedDays.lowerBound.adding(days: $0) }).days
        }
        refreshSummary()
    }

    /// The summary strip over the shown days.
    func refreshSummary() {
        summary = summarize(shownDays)
    }

    /// The totals of `days`; tracked time counts the entries the Filters
    /// and the search let through.
    func summarize(_ days: [TrackingDay]) -> CalendarSummary {
        CalendarSummary(
            days: days,
            calendar: calendar,
            entries: isFiltering ? entries.filter(passesFilters) : entries,
            activity: blocks,
            timeBlocks: timeBlocks.map(\.event.interval),
            now: clock.now
        )
    }
}
