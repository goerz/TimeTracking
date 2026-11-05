// ActivityCellTooltip: the heatmap cell's tooltip (activity.md §1.4).

/// What hovering a heatmap cell shows.
public struct ActivityCellTooltip: Sendable, Hashable {
    /// One line: an item (day rows) or a context with its average (others).
    public struct Line: Sendable, Hashable {
        public var context: String
        /// Subject and detail ("draft nvim (3 files)"); empty for context lines.
        public var text: String
        public var seconds: Int
        /// The device, when several devices are present.
        public var device: String?
    }

    /// "Thu Oct 29 · 09:00–10:00".
    public var title: String
    /// "about 47m active (MacBook)" or "about 40m per day over 5 days".
    public var summary: String
    /// At most five lines.
    public var lines: [Line]
    /// The lines not shown ("+ N more").
    public var moreCount: Int

    /// "+ 3 more", or `nil`.
    public var moreText: String? {
        moreCount > 0 ? "+ \(moreCount) more" : nil
    }
}

extension ActivitySummary {
    /// The tooltip of `row`'s cell at `hour`.
    public func cellTooltip(row: ActivityHeatmap.Row, hour: Int) -> ActivityCellTooltip {
        let hourText = "\(ActivityText.clock(hour: hour))–\(ActivityText.clock(hour: (hour + 1) % 24))"
        let rowDays = Set(row.days.map(\.description))
        let cellBlocks = blocks.filter { rowDays.contains($0.shownDay) && (ActivityAggregation.hourFractions(of: $0)[hour] ?? 0) > 0 }
        let severalDevices = Set(blocks.flatMap(\.deviceNames)).count > 1
        var seconds: [ActivityCellTooltip.Line: Double] = [:]
        for block in cellBlocks {
            let fraction = ActivityAggregation.hourFractions(of: block)[hour] ?? 0
            for item in selectedItems(block) {
                let isDay = row.days.count == 1
                let detail = [item.subject, item.detail].filter { !$0.isEmpty }.joined(separator: " ")
                let key = ActivityCellTooltip.Line(
                    context: item.context,
                    text: isDay ? detail : "",
                    seconds: 0,
                    device: isDay && severalDevices ? ActivityContext.deviceName(item.device) : nil
                )
                seconds[key, default: 0] += Double(item.seconds) * fraction
            }
        }
        let past = max(row.pastDays, 1)
        let divisor = row.days.count == 1 ? 1 : Double(past)
        let lines = seconds.map { key, value in
            var line = key
            line.seconds = Int((value / divisor).rounded())
            return line
        }
        .sorted { ($1.seconds, $0.context, $0.text) < ($0.seconds, $1.context, $1.text) }
        let cellSeconds = Int((row.minutes[hour] * 60).rounded())
        let summary: String
        if row.days.count == 1, let day = row.days.first {
            let devices = Set(cellBlocks.flatMap(\.deviceNames).map(ActivityContext.deviceName)).sorted().joined(separator: ", ")
            let about = cellBlocks.count > 1 ? "about " : ""
            summary = "\(about)\(ActivityText.duration(cellSeconds)) active" + (devices.isEmpty ? "" : " (\(devices))")
            return ActivityCellTooltip(
                title: "\(DayText.shortWeekday(day)) \(DayText.shortMonth(day)) \(day.day) · \(hourText)",
                summary: summary,
                lines: Array(lines.prefix(5)),
                moreCount: max(0, lines.count - 5)
            )
        }
        summary = "about \(ActivityText.duration(cellSeconds)) per day over \(row.pastDays) days"
        return ActivityCellTooltip(
            title: "\(row.label) · \(hourText)",
            summary: summary,
            lines: Array(lines.prefix(5)),
            moreCount: max(0, lines.count - 5)
        )
    }
}
