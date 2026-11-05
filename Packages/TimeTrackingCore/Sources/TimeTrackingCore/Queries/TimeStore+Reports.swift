// Report aggregation (spec_data_and_sync.md §7.3, §7.5; spec_reports.md §5).
// Each entry counts in the days it lies on, the running one up to the query
// time, its part on each day as one entry there; grouping uses the project's
// current area. One scan cuts the entries and sums them per project, task,
// and day, and the tree is built from those groups (§7.5's targets on the
// large dataset).

import Foundation
import GRDB

/// A project with the names its report keys resolve to (tombstones too, so
/// history keeps its names).
struct ReportProject {
    var id: ProjectID
    var name: String
    var archived: Bool
    var areaID: AreaID?
    var areaName: String?
    var areaColor: String?
    var areaOrder: Int
    var clientID: ClientID?
    var clientName: String?
}

/// What one scan of the entries looks at.
struct ReportScan {
    var needle = ""
    var now: Int64
    var lower = Int64.min
    var upper = Int64.max
}

/// The entries of one project, untrimmed task, and day.
struct ReportGroup {
    var projectKey: String?
    var task: String
    var day: TrackingDay
    var seconds = 0
    var count = 0
    var running = false
}

private struct ReportGroupKey: Hashable {
    var projectKey: String?
    var task: String
    var day: TrackingDay
}

/// The entries of one project, task, and day: their count and seconds.
struct ReportRow {
    var projectID: ProjectID?
    var project: ReportProject?
    /// The trimmed task.
    var task: String
    var day: TrackingDay
    /// The query granularity's period of `day`.
    var period: TrackingPeriod
    var seconds: Int
    var count: Int
    /// The running entry is among them.
    var running: Bool

    var clientID: ClientID? {
        project?.clientID
    }

    var clientName: String? {
        project?.clientName
    }

    var areaID: AreaID? {
        project?.areaID
    }

    var areaName: String? {
        project?.areaName
    }

    var areaColor: String? {
        project?.areaColor
    }

    var projectName: String? {
        project?.name
    }

    var projectArchived: Bool {
        project?.archived ?? false
    }

    func value(_ key: GroupKey) -> GroupKeyValue {
        switch key {
        case .client: .client(clientID)
        case .area: .area(areaID)
        case .project: .project(projectID)
        case .task: .task(task)
        case .day: .day(day)
        }
    }

    func name(_ key: GroupKey) -> String? {
        switch key {
        case .client: clientName
        case .area: areaName
        case .project: projectName
        case .task: task
        case .day: day.description
        }
    }

    /// The "by name" order of a node at level `key`.
    func sortKey(_ key: GroupKey) -> String {
        switch key {
        case .client: (clientName ?? "\u{10FFFF}").folded
        case .area:
            "\((clientName ?? "\u{10FFFF}").folded)\u{1F}\(String(format: "%06d", project?.areaOrder ?? 0))\u{1F}\((areaName ?? "").folded)"
        case .project: (projectName ?? "\u{10FFFF}").folded
        case .task: task.lowercased()
        case .day: day.description
        }
    }
}

extension TimeStore: Reporting {
    public func report(_ query: ReportQuery) throws -> ReportNode {
        try Self.tree(of: reportRows(query), query: query)
    }

    /// The report tree over rows already filtered by `query`.
    static func tree(of rows: [ReportRow], query: ReportQuery) -> ReportNode {
        var root = node(.total, name: nil, color: nil, rows: rows)
        root.children = children(of: rows, levels: query.groupBy[...])
        return root
    }

    public func series(_ query: ReportQuery) throws -> [(TrackingPeriod, [GroupKeyValue: Int])] {
        let rows = try reportRows(query)
        let periods = displayCalendar().periods(query.granularity, covering: query.days)
        var sums: [TrackingPeriod: [GroupKeyValue: Int]] = [:]
        for row in rows {
            let key = query.groupBy.first.map(row.value) ?? .total
            sums[row.period, default: [:]][key, default: 0] += row.seconds
        }
        return periods.map { ($0, sums[$0] ?? [:]) }
    }

    /// The matching entries whose stored `day` lies in the query's days,
    /// by start.
    public func entries(matching query: ReportQuery) throws -> [TimeEntry] {
        try entries(
            matching: query,
            where: "e.day >= ? AND e.day <= ?",
            [query.days.lowerBound.description, query.days.upperBound.description]
        )
    }

    /// The live entries satisfying `clause` that pass the query's filter, by start.
    func entries(matching query: ReportQuery, where clause: String, _ arguments: [any DatabaseValueConvertible]) throws -> [TimeEntry] {
        let projects = try reportProjects()
        let filter = query.filter
        let needle = filter.taskContains?.folded ?? ""
        return try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT \(TimeEntry.columns) FROM time_entry e
                WHERE e.deleted_at IS NULL AND \(clause) AND (? = '' OR instr(e.task_key, ?) > 0)
                ORDER BY e.start, e.id
                """,
                arguments: StatementArguments(arguments + [needle, needle])
            )
        }
        .map(TimeEntry.init(row:))
        .filter { entry in
            if let bounds = query.bounds, entry.start < bounds.start || entry.start >= bounds.end {
                return false
            }
            let project = entry.projectID.flatMap { projects[$0.rawValue] }
            return Self.passes(project, projectID: entry.projectID, filter: filter)
                && Self.matches(filter.search, task: entry.task, project: project)
        }
    }

    /// The groups of entries matching `query`, and the mapped health time.
    func reportRows(_ query: ReportQuery) throws -> [ReportRow] {
        let projects = try reportProjects()
        let filter = query.filter
        let needle = filter.taskContains?.folded ?? ""
        let now = Int64(clock.now.timeIntervalSince1970.rounded(.down))
        let lower = query.bounds.map { Int64($0.start.timeIntervalSince1970.rounded(.up)) } ?? Int64.min
        let upper = query.bounds.map { Int64($0.end.timeIntervalSince1970.rounded(.up)) } ?? Int64.max
        let scan = ReportScan(needle: needle, now: now, lower: lower, upper: upper)
        let groups = try shownGroups(days: query.days, scan: scan, in: displayCalendar(timeZone: timeZone()))
        var periods: [TrackingDay: TrackingPeriod] = [:]
        let entryRows = groups.compactMap { group -> ReportRow? in
            let project = group.projectKey.flatMap { projects[$0] }
            let projectID = project?.id ?? group.projectKey.flatMap(ProjectID.init)
            guard Self.passes(project, projectID: projectID, filter: filter),
                  Self.matches(filter.search, task: group.task, project: project)
            else {
                return nil
            }
            let period = periods[group.day] ?? TrackingPeriod(query.granularity, containing: group.day, rangeStart: query.days.lowerBound)
            periods[group.day] = period
            return ReportRow(
                projectID: projectID,
                project: project,
                task: group.task.trimmed,
                day: group.day,
                period: period,
                seconds: group.seconds,
                count: group.count,
                running: group.running
            )
        }
        return try entryRows + (query.includeHealth ? healthReportRows(query) : [])
    }

    /// The groups by the days the app shows, each part of an entry counting
    /// as one entry of its day.
    func shownGroups(days: ClosedRange<TrackingDay>, scan: ReportScan, in calendar: TrackingCalendar) throws -> [ReportGroup] {
        let reach = calendar.reach(of: days)
        var cutter = ReportDayCutter(midnightHour: calendar.midnightHour, now: scan.now)
        var groups: [ReportGroupKey: ReportGroup] = [:]
        try read { database in
            let rows = try Row.fetchCursor(
                database,
                sql: """
                SELECT e.project_id, e.task, e.day, e.time_zone, e.start, e."end"
                FROM time_entry e
                WHERE e.deleted_at IS NULL AND e.start < ? AND COALESCE(e."end", ?) > ?
                  AND (? = '' OR instr(e.task_key, ?) > 0) AND e.start >= ? AND e.start < ?
                """,
                arguments: [
                    Time.seconds(reach.end), scan.now, Time.seconds(reach.start),
                    scan.needle, scan.needle, scan.lower, scan.upper,
                ]
            )
            while let row = try rows.next() {
                let projectKey: String? = row["project_id"]
                let task: String = row["task"]
                let isRunning = (row["end"] as Int64?) == nil
                let parts = cutter.parts(of: row)
                for (index, part) in parts.enumerated() where days.contains(part.day) {
                    let key = ReportGroupKey(projectKey: projectKey, task: task, day: part.day)
                    var group = groups[key] ?? ReportGroup(projectKey: projectKey, task: task, day: part.day)
                    group.seconds += part.seconds
                    group.count += 1
                    group.running = group.running || (isRunning && index == parts.count - 1)
                    groups[key] = group
                }
            }
        }
        return Array(groups.values)
    }

    /// Every project by its id text, with its area and client.
    func reportProjects() throws -> [String: ReportProject] {
        try read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT p.id, p.name, p.archived, a.id AS area_id, a.name AS area_name, a.color AS area_color,
                  a.sort_order AS area_order, c.id AS client_id, c.name AS client_name
                FROM project p LEFT JOIN area a ON a.id = p.area_id LEFT JOIN client c ON c.id = a.client_id
                """
            )
            var projects: [String: ReportProject] = [:]
            for row in rows {
                let key: String = row["id"]
                guard let id = ProjectID(key) else {
                    continue
                }
                projects[key] = ReportProject(
                    id: id,
                    name: row["name"],
                    archived: row["archived"],
                    areaID: row.uuid("area_id"),
                    areaName: row["area_name"],
                    areaColor: row["area_color"],
                    areaOrder: row["area_order"] ?? 0,
                    clientID: row.uuid("client_id"),
                    clientName: row["client_name"]
                )
            }
            return projects
        }
    }

    /// The filter's client, area, project, and archive rules (the task rule
    /// runs in SQL).
    static func passes(_ project: ReportProject?, projectID: ProjectID?, filter: EntryFilter) -> Bool {
        guard let projectID else {
            return filter.includeNoProject && (filter.projects == nil || filter.projectsIncludeNone)
                && (filter.areas == nil || filter.areasIncludeNone) && (filter.clients == nil || filter.clientsIncludeNone)
                && (filter.scope == nil || filter.scopeIncludesNone)
        }
        return !filter.noProjectOnly && (filter.includeArchived || !(project?.archived ?? false))
            && (filter.scope.map { $0.contains(project: projectID, area: project?.areaID, client: project?.clientID) } ?? true)
            && (filter.projects.map { $0.contains(projectID) } ?? true)
            && (filter.areas.map { ids in project?.areaID.map(ids.contains) ?? false } ?? true)
            && (filter.clients.map { ids in project?.clientID.map(ids.contains) ?? false } ?? true)
    }

    /// The Reports search: every word in the task or the project, area, or
    /// client name.
    static func matches(_ search: String, task: String, project: ReportProject?) -> Bool {
        let words = search.folded.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return true
        }
        let texts = [task, project?.name ?? "", project?.areaName ?? "", project?.clientName ?? ""].map(\.folded)
        return words.allSatisfy { word in texts.contains { $0.contains(word) } }
    }

    private static func node(_ key: GroupKeyValue, name: String?, color: String?, rows: [ReportRow]) -> ReportNode {
        var buckets: [TrackingPeriod: Int] = [:]
        var entryBuckets: [TrackingPeriod: Int] = [:]
        var seconds = 0
        var count = 0
        for row in rows {
            buckets[row.period, default: 0] += row.seconds
            entryBuckets[row.period, default: 0] += row.count
            seconds += row.seconds
            count += row.count
        }
        return ReportNode(
            key: key,
            name: name,
            color: color,
            seconds: seconds,
            entryCount: count,
            buckets: buckets,
            entryBuckets: entryBuckets
        )
    }

    private static func children(of rows: [ReportRow], levels: ArraySlice<GroupKey>) -> [ReportNode] {
        guard let level = levels.first else {
            return []
        }
        let groups = Dictionary(grouping: rows) { $0.value(level) }
        return groups.values
            .map { ($0[0].sortKey(level), "\($0[0].value(level))", $0) }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map { _, _, group in
                let first = group[0]
                let color = level == .area || level == .project ? first.areaColor : nil
                var node = node(first.value(level), name: first.name(level), color: color, rows: group)
                node.isArchived = level == .project && first.projectArchived
                node.children = children(of: group, levels: levels.dropFirst())
                return node
            }
    }
}
