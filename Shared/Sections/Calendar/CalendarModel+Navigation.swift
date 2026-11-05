// The Calendar's navigation: Today, the arrows, sideways scrolling, both
// zooms, columns, and the router's `showCalendar` request
// (spec_calendar.md §1.2, §1.3).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    // MARK: Navigation (§1.2)

    /// ⌘T: today at position ⌈n / 2⌉ of the whole days that fit.
    func goToToday() async {
        centersTodayOnLayout = false
        viewport.center(today)
        await loaded()
    }

    /// ← / → and the arrows by `count` days, snapped so a day starts at
    /// the left edge; with ⌥ or ⇧ by the whole days in view.
    func shift(days count: Int) async {
        step(days: count)
        await loaded()
    }

    /// The arrows' step without waiting for the data (the view animates it).
    func step(days count: Int) {
        centersTodayOnLayout = false
        // A trackpad's momentum would carry the days off the snapped edge.
        ignoresMomentum = true
        viewport.step(days: count)
    }

    /// A click on a day header makes it the first day; ⌥-click shows it
    /// alone, as wide as the viewport.
    func showDay(_ day: TrackingDay, alone: Bool = false) async {
        reveal(day, alone: alone)
        await loaded()
    }

    /// `showDay` without waiting for the data (the view animates it).
    func reveal(_ day: TrackingDay, alone: Bool = false) {
        centersTodayOnLayout = false
        ignoresMomentum = true
        if alone {
            viewport.showAlone(day)
        } else {
            viewport.show(day)
        }
    }

    /// ⌘+, ⌘−, ⌘0 (the view keeps the center time in place).
    func zoom(by step: Int) {
        switch step {
        case 1: pointsPerHour = CalendarZoom.zoomedIn(pointsPerHour)
        case -1: pointsPerHour = CalendarZoom.zoomedOut(pointsPerHour)
        default: pointsPerHour = CalendarZoom.defaultPointsPerHour
        }
    }

    /// ⌥⌘A / ⌥⌘K.
    func toggle(_ column: CalendarColumn) async {
        switch column {
        case .activity: showsActivity.toggle()
        case .calendar: showsCalendar.toggle()
        case .tracked: return
        }
        await reload()
    }

    /// `showCalendar(day:hour:highlight:)`: `day` leftmost, `hour` at the
    /// top (the first block's hour when nil), Activity on, the highlight
    /// pulsed for 1.5 s; zoom and day count unchanged.
    func apply(_ request: CalendarRequest) async {
        centersTodayOnLayout = false
        viewport.show(request.day)
        showsActivity = true
        await reload()
        let firstBlock = blocks.filter { $0.shownDay == request.day.description }.map(\.start).min()
        let hour = request.hour.map(axisHour(clock:))
            ?? firstBlock.map { axis(request.day).y($0) / pointsPerHour }
            ?? axisHour(clock: 8)
        scrollRequest = (hour, (scrollRequest?.serial ?? 0) + 1)
        if let highlight = request.highlight {
            self.highlight = (request.day, highlight)
            pulseEnds = clock.now + 1.5
        } else {
            highlight = nil
        }
    }

    /// Whether `block` pulses for the current highlight.
    func isHighlighted(_ block: ActivityBlock) -> Bool {
        guard let highlight, block.shownDay == highlight.day.description else {
            return false
        }
        switch highlight.highlight {
        case let .hour(hour):
            let start = axis(highlight.day).y(block.start) / pointsPerHour
            let end = axis(highlight.day).y(block.end) / pointsPerHour
            let top = axisHour(clock: hour)
            return start < top + 1 && end > top
        case let .context(context):
            return block.contexts.contains(context)
        }
    }

    /// Ends the pulse (the view calls it after 1.5 s).
    func endPulse() {
        highlight = nil
        pulseEnds = nil
    }
}
