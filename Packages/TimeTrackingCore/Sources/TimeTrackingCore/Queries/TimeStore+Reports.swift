// Report aggregation (spec_data_and_sync.md §7.3, spec_planner_reports.md §5).
// Each entry whose day lies in the range counts whole in its day, the
// running one up to the query time; grouping uses the project's current area.

import Foundation
import GRDB

/// One entry with the names its report keys resolve to.
struct ReportRow {
    var entry: TimeEntry
    var seconds: Int
    var clientID: ClientID?
    var clientName: String?
    var areaID: AreaID?
    var areaName: String?
    var areaColor: String?
    var areaOrder: Int
    var projectName: String?
    var projectArchived: Bool

    func value(_ key: GroupKey) -> GroupKeyValue {
        switch key {
        case .client: .client(clientID)
        case .area: .area(areaID)
        case .project: .project(entry.projectID)
        case .task: .task(entry.task.trimmed)
        case .day: .day(entry.day)
        }
    }

    func name(_ key: GroupKey) -> String? {
        switch key {
        case .client: clientName
        case .area: areaName
        case .project: projectName
        case .task: entry.task.trimmed
        case .day: entry.day.description
        }
    }

    /// The "by name" order of a node at level `key`.
    func sortKey(_ key: GroupKey) -> String {
        switch key {
        case .client: (clientName ?? "\u{10FFFF}").folded
        case .area: "\((clientName ?? "\u{10FFFF}").folded)\u{1F}\(String(format: "%06d", areaOrder))\u{1F}\((areaName ?? "").folded)"
        case .project: (projectName ?? "\u{10FFFF}").folded
        case .task: entry.task.trimmed.lowercased()
        case .day: entry.day.description
        }
    }
}

extension TimeStore: Reporting {
    public func report(_ query: ReportQuery) throws -> ReportNode {
        let rows = try reportRows(query)
        var root = Self.node(.total, name: nil, color: nil, rows: rows, query: query)
        root.children = Self.children(of: rows, levels: query.groupBy[...], query: query)
        return root
    }

    public func series(_ query: ReportQuery) throws -> [(TrackingPeriod, [GroupKeyValue: Int])] {
        let rows = try reportRows(query)
        let periods = TrackingCalendar(timeZone: .current).periods(query.granularity, covering: query.days)
        var sums: [TrackingPeriod: [GroupKeyValue: Int]] = [:]
        for row in rows {
            let key = query.groupBy.first.map(row.value) ?? .total
            sums[Self.period(of: row, query: query), default: [:]][key, default: 0] += row.seconds
        }
        return periods.map { ($0, sums[$0] ?? [:]) }
    }

    public func entries(matching query: ReportQuery) throws -> [TimeEntry] {
        try reportRows(query).map(\.entry)
    }

    func reportRows(_ query: ReportQuery) throws -> [ReportRow] {
        let now = clock.now
        let rows = try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT \(TimeEntry.columns), p.name AS project_name, p.archived AS project_archived,
                  a.id AS area_id, a.name AS area_name, a.color AS area_color, a.sort_order AS area_order,
                  c.id AS client_id, c.name AS client_name
                FROM time_entry e LEFT JOIN project p ON p.id = e.project_id
                  LEFT JOIN area a ON a.id = p.area_id LEFT JOIN client c ON c.id = a.client_id
                WHERE e.deleted_at IS NULL AND e.day >= ? AND e.day <= ?
                ORDER BY e.start, e.id
                """,
                arguments: [query.days.lowerBound.description, query.days.upperBound.description]
            )
        }
        let filter = query.filter
        let needle = filter.taskContains?.folded ?? ""
        return rows.map { row in
            let entry = TimeEntry(row: row)
            return ReportRow(
                entry: entry,
                seconds: entry.seconds(at: now),
                clientID: row.uuid("client_id"),
                clientName: row["client_name"],
                areaID: row.uuid("area_id"),
                areaName: row["area_name"],
                areaColor: row["area_color"],
                areaOrder: row["area_order"] ?? 0,
                projectName: row["project_name"],
                projectArchived: row["project_archived"] ?? false
            )
        }
        .filter { row in
            guard let projectID = row.entry.projectID else {
                return filter.includeNoProject && filter.projects == nil && filter.areas == nil && filter.clients == nil
                    && (needle.isEmpty || row.entry.task.folded.contains(needle))
            }
            return (filter.includeArchived || !row.projectArchived)
                && (filter.projects.map { $0.contains(projectID) } ?? true)
                && (filter.areas.map { ids in row.areaID.map(ids.contains) ?? false } ?? true)
                && (filter.clients.map { ids in row.clientID.map(ids.contains) ?? false } ?? true)
                && (needle.isEmpty || row.entry.task.folded.contains(needle))
        }
    }

    private static func period(of row: ReportRow, query: ReportQuery) -> TrackingPeriod {
        TrackingPeriod(query.granularity, containing: row.entry.day, rangeStart: query.days.lowerBound)
    }

    private static func node(_ key: GroupKeyValue, name: String?, color: String?, rows: [ReportRow], query: ReportQuery) -> ReportNode {
        var buckets: [TrackingPeriod: Int] = [:]
        var entryBuckets: [TrackingPeriod: Int] = [:]
        for row in rows {
            let period = period(of: row, query: query)
            buckets[period, default: 0] += row.seconds
            entryBuckets[period, default: 0] += 1
        }
        return ReportNode(
            key: key,
            name: name,
            color: color,
            seconds: rows.reduce(0) { $0 + $1.seconds },
            entryCount: rows.count,
            buckets: buckets,
            entryBuckets: entryBuckets
        )
    }

    private static func children(of rows: [ReportRow], levels: ArraySlice<GroupKey>, query: ReportQuery) -> [ReportNode] {
        guard let level = levels.first else {
            return []
        }
        let groups = Dictionary(grouping: rows) { $0.value(level) }
        return groups.values
            .sorted { lhs, rhs in lhs[0].sortKey(level) < rhs[0].sortKey(level) }
            .map { group in
                let first = group[0]
                let color = level == .area || level == .project ? first.areaColor : nil
                var node = node(first.value(level), name: first.name(level), color: color, rows: group, query: query)
                node.children = children(of: group, levels: levels.dropFirst(), query: query)
                return node
            }
    }
}
