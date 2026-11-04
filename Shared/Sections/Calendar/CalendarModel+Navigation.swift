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
        viewport.step(days: count)
    }

    /// A click on a day header makes it the first day; ⌥-click shows it
    /// alone, as wide as the viewport.
    func showDay(_ day: TrackingDay, alone: Bool = false) async {
        centersTodayOnLayout = false
        if alone {
            viewport.showAlone(day)
        } else {
            viewport.show(day)
        }
        await loaded()
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
        let firstBlock = blocks.filter { $0.localDay == request.day.description }.map(\.start).min()
        let hour = request.hour.map(Double.init)
            ?? firstBlock.map { axis(request.day).y($0) / pointsPerHour }
            ?? 8
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
        guard let highlight, block.localDay == highlight.day.description else {
            return false
        }
        switch highlight.highlight {
        case let .hour(hour):
            let start = axis(highlight.day).y(block.start) / pointsPerHour
            let end = axis(highlight.day).y(block.end) / pointsPerHour
            return start < Double(hour + 1) && end > Double(hour)
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
