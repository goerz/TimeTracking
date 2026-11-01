// ActivityHeatmap: active time by hour (spec_activity.md §1.4).

import Foundation

/// The heatmap's rows: days, ISO weeks, or months.
public struct ActivityHeatmap: Sendable {
    public enum Mode: Sendable, Hashable {
        case days
        case weeks
        case months
    }

    /// One row of 24 cells.
    public struct Row: Sendable, Identifiable {
        public var id: String
        /// "Thu 29", "W44", "Oct 2026", or "All".
        public var label: String
        /// The Monday's date of a week row ("Oct 26").
        public var sublabel: String?
        /// The days of the row inside the range.
        public var days: [TrackingDay]
        /// Those not after today; averages divide by their count.
        public var pastDays: Int
        /// Minutes per hour: active minutes (day rows) or the average per past day.
        public var minutes: [Double]
        /// The row total (day rows) or the average per past day (others), in seconds.
        public var seconds: Int
        /// No time in the row (dimmed label).
        public var isEmpty: Bool

        /// "9h 06m" or "6h 15m avg/day".
        public var totalText: String {
            id.hasPrefix("day:") ? ActivityText.duration(seconds) : "\(ActivityText.duration(seconds)) avg/day"
        }
    }

    public var mode: Mode
    public var rows: [Row]
    /// The "All" row of week and month rows.
    public var footer: Row?

    /// The shading level 0 to 4 of a cell's minutes (§1.4).
    public static func level(minutes: Double) -> Int {
        let rounded = Int(minutes.rounded())
        switch rounded {
        case ...0: return 0
        case 1 ... 15: return 1
        case 16 ... 30: return 2
        case 31 ... 45: return 3
        default: return 4
        }
    }

    /// The row mode for a range of `dayCount` days.
    public static func mode(dayCount: Int) -> Mode {
        switch dayCount {
        case ...7: .days
        case 8 ... 98: .weeks
        default: .months
        }
    }

    /// The hour labels: 0, 3, …, 21.
    public static let labeledHours = stride(from: 0, to: 24, by: 3).map(\.self)
}

extension ActivitySummary {
    /// Seconds per local hour per day under the filter.
    var hourSecondsByDay: [TrackingDay: [Int]] {
        var result: [TrackingDay: [Int]] = [:]
        for block in blocks {
            guard let day = TrackingDay(block.localDay) else {
                continue
            }
            var hours = result[day] ?? Array(repeating: 0, count: 24)
            for (hour, seconds) in ActivityAggregation.hourShares(of: block, total: value(block)) {
                hours[hour] += seconds
            }
            result[day] = hours
        }
        return result
    }

    /// The heatmap of the range (§1.4).
    public var heatmap: ActivityHeatmap {
        let all = Self.days(input.days)
        let byDay = hourSecondsByDay
        let mode = ActivityHeatmap.mode(dayCount: all.count)
        switch mode {
        case .days:
            let rows = all.map { day in
                row(id: "day:\(day)", label: "\(DayText.shortWeekday(day)) \(day.day)", days: [day], byDay: byDay, average: false)
            }
            return ActivityHeatmap(mode: mode, rows: rows, footer: nil)
        case .weeks:
            let groups = Dictionary(grouping: all) { $0.adding(days: 1 - $0.isoWeekday) }
            let rows = groups.keys.sorted().map { monday in
                var row = row(
                    id: "week:\(monday)",
                    label: "W\(monday.isoWeek.week)",
                    days: groups[monday] ?? [],
                    byDay: byDay,
                    average: true
                )
                row.sublabel = "\(DayText.shortMonth(monday)) \(monday.day)"
                return row
            }
            return ActivityHeatmap(mode: mode, rows: rows, footer: footer(all, byDay: byDay))
        case .months:
            let groups = Dictionary(grouping: all) { TrackingDay(year: $0.year, month: $0.month, day: 1) }
            let rows = groups.keys.sorted().map { first in
                row(
                    id: "month:\(first)",
                    label: "\(DayText.shortMonth(first)) \(first.year)",
                    days: groups[first] ?? [],
                    byDay: byDay,
                    average: true
                )
            }
            return ActivityHeatmap(mode: mode, rows: rows, footer: footer(all, byDay: byDay))
        }
    }

    private func row(id: String, label: String, days: [TrackingDay], byDay: [TrackingDay: [Int]], average: Bool) -> ActivityHeatmap.Row {
        let past = days.filter { $0 <= input.today }.count
        var seconds = Array(repeating: 0, count: 24)
        for day in days {
            for (hour, value) in (byDay[day] ?? []).enumerated() {
                seconds[hour] += value
            }
        }
        let total = seconds.reduce(0, +)
        let divisor = average ? Double(max(past, 1)) : 1
        return ActivityHeatmap.Row(
            id: id,
            label: label,
            sublabel: nil,
            days: days.sorted(),
            pastDays: past,
            minutes: seconds.map { Double($0) / 60 / divisor },
            seconds: average ? (past == 0 ? 0 : total / past) : total,
            isEmpty: total == 0
        )
    }

    private func footer(_ all: [TrackingDay], byDay: [TrackingDay: [Int]]) -> ActivityHeatmap.Row {
        row(id: "all", label: "All", days: all, byDay: byDay, average: true)
    }

    /// The footer cell's tooltip: "09:00–10:00 · 41h 20m over 62 days · about 40m per day".
    public func footerTooltip(hour: Int) -> String {
        let past = pastDays
        let seconds = past.reduce(0) { $0 + (hourSecondsByDay[$1]?[hour] ?? 0) }
        let average = past.isEmpty ? 0 : seconds / past.count
        let range = "\(ActivityText.clock(hour: hour))–\(ActivityText.clock(hour: (hour + 1) % 24))"
        return "\(range) · \(ActivityText.duration(seconds)) over \(past.count) days · about \(ActivityText.duration(average)) per day"
    }
}
