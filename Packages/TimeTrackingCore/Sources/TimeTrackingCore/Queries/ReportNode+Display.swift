// Breakdown display: node names, sorting, and duration texts
// (spec_reports.md §4.1, §5).

import Foundation

/// The breakdown table's sortable columns.
public enum ReportColumn: String, Codable, Sendable, CaseIterable {
    case name
    case loggedTime = "logged_time"
    case share
    case entries
}

extension ReportNode {
    /// The name the breakdown shows at level `level`: "No client", "No area",
    /// "No project", "(no task)", "Mon 10/26".
    public func displayName(level _: GroupKey) -> String {
        switch key {
        case .total:
            "Total"
        case let .client(id):
            id == nil ? "No client" : name ?? ""
        case let .area(id):
            id == nil ? "No area" : name ?? ""
        case let .project(id):
            id == nil ? "No project" : name ?? ""
        case let .task(text):
            text.isEmpty ? "(no task)" : text
        case let .day(day):
            DayText.weekdayShortDate(day)
        }
    }

    /// The tree with each level's children sorted by `column`; the level's
    /// "by name" order (the stored order) breaks ties. Share sorts like
    /// Logged time.
    public func sorted(by column: ReportColumn, ascending: Bool) -> Self {
        var copy = self
        let indexed = children.enumerated().map { ($0.offset, $0.element.sorted(by: column, ascending: ascending)) }
        copy.children = indexed.sorted { lhs, rhs in
            let left: Int
            let right: Int
            switch column {
            case .name:
                left = lhs.0
                right = rhs.0
            case .loggedTime, .share:
                left = lhs.1.seconds
                right = rhs.1.seconds
            case .entries:
                left = lhs.1.entryCount
                right = rhs.1.entryCount
            }
            if left != right {
                return ascending ? left < right : left > right
            }
            return lhs.0 < rhs.0
        }
        .map(\.1)
        return copy
    }

    /// The node at `path` below this one.
    public func node(at path: [GroupKeyValue]) -> Self? {
        guard let first = path.first else {
            return self
        }
        return children.first { $0.key == first }?.node(at: Array(path.dropFirst()))
    }

    /// Key paths of every node with children (Expand All).
    public var expandablePaths: [[GroupKeyValue]] {
        children.flatMap { child -> [[GroupKeyValue]] in
            guard !child.children.isEmpty else {
                return []
            }
            return [[child.key]] + child.expandablePaths.map { [child.key] + $0 }
        }
    }
}

/// Duration and share texts of Reports.
public enum ReportText {
    /// Tiles: "18h 50m", "50m", "0h"; hours never roll into days.
    public static func tile(_ seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let hours = minutes / 60
        if hours == 0 {
            return minutes == 0 ? "0h" : "\(minutes)m"
        }
        return minutes.isMultiple(of: 60) ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
    }

    /// The caption under the Average per day tile: "over 4 of 4 days".
    public static func averageCaption(_ summary: ReportSummary?) -> String {
        "over \(summary?.daysWithEntries ?? 0) of \(summary?.elapsedDays ?? 0) days"
    }

    /// Bar totals and the average rule: "9h 26m", "0h".
    public static func bar(_ seconds: Int) -> String {
        tile(seconds)
    }

    /// To the second: "12h 50m 14s", "19m 54s", "4s"; tooltips pad
    /// "6h 10m 03s".
    public static func seconds(_ seconds: Int, padded: Bool = false) -> String {
        let value = max(seconds, 0)
        let hours = value / 3600
        let minutes = value / 60 % 60
        let secs = value % 60
        let pad = { (number: Int) in padded ? String(format: "%02d", number) : String(number) }
        if hours > 0 {
            return "\(hours)h \(pad(minutes))m \(pad(secs))s"
        }
        if minutes > 0 {
            return "\(minutes)m \(pad(secs))s"
        }
        return "\(secs)s"
    }

    /// Share of the report total with one decimal: "68.1%".
    public static func share(_ seconds: Int, of total: Int) -> String {
        String(format: "%.1f%%", total == 0 ? 0 : Double(seconds) * 100 / Double(total))
    }

    /// The bar width as a fraction of the total.
    public static func fraction(_ seconds: Int, of total: Int) -> Double {
        total == 0 ? 0 : Double(seconds) / Double(total)
    }
}
