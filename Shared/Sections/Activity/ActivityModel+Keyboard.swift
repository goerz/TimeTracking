// ActivityModel+Keyboard: the keyboard focus inside the heatmap and the bars
// (spec_activity.md §2).

import TimeTrackingCore

extension ActivityModel {
    private var midnightHour: Int {
        range.calendar.midnightHour
    }

    // MARK: Heatmap

    /// The heatmap took the focus: its first cell unless one is still shown.
    func heatmapFocused() {
        guard let heatmap = summary?.heatmap, focusedCell.flatMap(heatmap.row(of:)) == nil else {
            return
        }
        focusedCell = heatmap.firstCell(midnightHour: midnightHour)
    }

    func moveFocusedCell(_ move: ActivityFocusMove) {
        focusedCell = summary?.heatmap.cell(move, from: focusedCell, midnightHour: midnightHour)
    }

    /// Return on a cell: as a click.
    func openFocusedCell() {
        if let cell = focusedCell, let row = summary?.heatmap.row(of: cell) {
            showInCalendar(row: row, hour: cell.hour)
        }
    }

    // MARK: Bars

    /// The chart took the focus: its first bar unless one is still shown.
    func barsFocused() {
        guard let bars = summary?.bars, focusedBar.flatMap(bars.bar(of:)) == nil else {
            return
        }
        focusedBar = bars.firstTarget
    }

    func moveFocusedBar(_ move: ActivityFocusMove) {
        focusedBar = summary?.bars.target(move, from: focusedBar)
    }

    /// Return on a bar or segment: as a click.
    func openFocusedBar() {
        if let target = focusedBar, let bars = summary?.bars {
            showInCalendar(target, in: bars)
        }
    }
}
