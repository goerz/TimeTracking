// Structure queries and the consistency check (spec_data_and_sync.md §1.1 to §1.3, §3.3, §7.2).

import Foundation
import GRDB

extension TimeStore: StructureReading {
    public func clients(includeRetired: Bool) throws -> [Client] {
        try read { database in
            let active = try Set(String.fetchAll(
                database,
                sql: """
                SELECT DISTINCT a.client_id FROM project p JOIN area a ON a.id = p.area_id
                WHERE p.deleted_at IS NULL AND p.archived = 0 AND a.deleted_at IS NULL
                """
            ))
            return try Row.fetchAll(database, sql: "SELECT * FROM client WHERE deleted_at IS NULL")
                .map { row in
                    var client = Client(row: row)
                    client.isRetired = !active.contains(client.id.rawValue)
                    return client
                }
                .filter { includeRetired || !$0.isRetired }
                .sorted { ($0.name.folded, $0.id) < ($1.name.folded, $1.id) }
        }
    }

    public func areas(of client: ClientID?, includeRetired: Bool) throws -> [Area] {
        let clients = try Dictionary(uniqueKeysWithValues: clients(includeRetired: true).map { ($0.id, $0.name.folded) })
        let areas = try read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT * FROM area WHERE deleted_at IS NULL AND (? IS NULL OR client_id = ?)",
                arguments: [client?.rawValue, client?.rawValue]
            ).map(Area.init(row:))
        }
        return areas
            .filter { includeRetired || !$0.isRetired }
            .sorted { lhs, rhs in
                let left = (clients[lhs.clientID] ?? "", lhs.clientID, lhs.sortOrder, lhs.name.folded)
                let right = (clients[rhs.clientID] ?? "", rhs.clientID, rhs.sortOrder, rhs.name.folded)
                return left < right
            }
    }

    public func projects(filter: ProjectFilter) throws -> [ProjectRow] {
        let stateClause = switch filter.state {
        case .active: " AND p.archived = 0"
        case .archived: " AND p.archived = 1"
        case .all: ""
        }
        let search = filter.search?.folded ?? ""
        return try projectRows(where: stateClause, arguments: []).filter { row in
            (filter.areaIDs.map { $0.contains(row.project.areaID) } ?? true)
                && (filter.clientIDs.map { ids in row.client.map { ids.contains($0.id) } ?? false } ?? true)
                && (search.isEmpty || [row.project.name, row.area?.name ?? "", row.client?.name ?? ""]
                    .contains { $0.folded.contains(search) })
        }
        .sorted { ($0.project.name.folded, $0.project.id) < ($1.project.name.folded, $1.project.id) }
    }

    /// The seconds tracked per project in the inclusive `days` (each entry
    /// counts in the days it lies on, the running one to now); projects
    /// without an entry in the range are absent (spec_projects.md §2.4).
    public func projectSeconds(days: ClosedRange<TrackingDay>) throws -> [ProjectID: Int] {
        let now = Time.seconds(clock.now)
        let hour = displayCalendar(timeZone: timeZone()).midnightHour
        guard hour == 0 else {
            let groups = try shownGroups(days: days, scan: ReportScan(now: now), midnightHour: hour)
            return groups.reduce(into: [:]) { result, group in
                if let id = group.projectKey.flatMap(ProjectID.init) {
                    result[id, default: 0] += group.seconds
                }
            }
        }
        let rows = try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT e.project_id, SUM(MAX(0, COALESCE(e."end", ?) - e.start)) AS seconds
                FROM time_entry e
                WHERE e.deleted_at IS NULL AND e.project_id IS NOT NULL AND e.day >= ? AND e.day <= ?
                GROUP BY e.project_id
                """,
                arguments: [now, days.lowerBound.description, days.upperBound.description]
            )
        }
        var result: [ProjectID: Int] = [:]
        for row in rows {
            if let id = ProjectID(row["project_id"] as String) {
                result[id] = row["seconds"]
            }
        }
        return result
    }

    /// The live project `id` as `projects(filter:)` lists it, archived or
    /// not; `nil` when it is missing or deleted.
    public func projectRow(_ id: ProjectID) throws -> ProjectRow? {
        try projectRows(where: " AND p.id = ?", arguments: [id.rawValue]).first
    }

    /// Live projects with area, client, and usage; `clause` narrows the
    /// `WHERE` on the project table `p`, with `arguments` for its `?`.
    private func projectRows(where clause: String, arguments: StatementArguments) throws -> [ProjectRow] {
        let now = Time.seconds(clock.now)
        let rows = try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT p.*, COUNT(e.id) AS entry_count, MAX(e.start) AS last_used,
                  COALESCE(SUM(COALESCE(e."end", ?) - e.start), 0) AS total
                FROM project p LEFT JOIN time_entry e ON e.project_id = p.id AND e.deleted_at IS NULL
                WHERE p.deleted_at IS NULL\(clause)
                GROUP BY p.id
                """,
                arguments: [now] + arguments
            )
        }
        let areas = try Dictionary(uniqueKeysWithValues: areas(of: nil, includeRetired: true).map { ($0.id, $0) })
        let clients = try Dictionary(uniqueKeysWithValues: clients(includeRetired: true).map { ($0.id, $0) })
        return rows.map { row in
            let project = Project(row: row)
            let area = areas[project.areaID]
            return ProjectRow(
                project: project,
                area: area,
                client: area.flatMap { clients[$0.clientID] },
                entryCount: row["entry_count"],
                lastUsed: Time.date(optional: row["last_used"] as Int64?),
                totalSeconds: row["total"]
            )
        }
    }

    public func project(_ id: ProjectID) throws -> Project? {
        try project(id, includeDeleted: false)
    }

    /// Any project, also a tombstone (for display of history).
    public func project(_ id: ProjectID, includeDeleted: Bool) throws -> Project? {
        try read { try StoreQueries.project(id, includeDeleted: includeDeleted, in: $0) }
    }

    public func projectTree(includeArchived: Bool) throws -> [ClientNode] {
        let projects = try projects(filter: ProjectFilter(state: includeArchived ? .all : .active))
        let byArea = Dictionary(grouping: projects.map(\.project), by: \.areaID)
        let areas = try Dictionary(grouping: areas(of: nil, includeRetired: includeArchived), by: \.clientID)
        return try clients(includeRetired: true).map { client in
            ClientNode(client: client, areas: (areas[client.id] ?? []).map { area in
                AreaNode(area: area, projects: (byArea[area.id] ?? []).sorted { $0.name.folded < $1.name.folded })
            })
        }
    }

    public func searchProjects(_ query: String, limit: Int) throws -> [ProjectRow] {
        let needle = query.folded
        let rows = try projects(filter: ProjectFilter(state: .active))
        guard !needle.isEmpty else {
            return Array(rows.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }.prefix(limit))
        }
        let scored = rows.compactMap { row -> (ProjectRow, Int)? in
            let score = Self.matchScore(needle, project: row.project.name, area: row.area?.name, client: row.client?.name)
            return score.map { (row, $0) }
        }
        return scored
            .sorted { ($0.1, $1.0.lastUsed ?? .distantPast) > ($1.1, $0.0.lastUsed ?? .distantPast) }
            .prefix(limit)
            .map(\.0)
    }

    public func devices() throws -> [Device] {
        try read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM device ORDER BY name, id").map(Device.init(row:))
        }
    }

    /// The fuzzy score: prefix of the project name, substring of it, of the
    /// area or client, or a subsequence of all three; `nil` for no match.
    static func matchScore(_ needle: String, project: String, area: String?, client: String?) -> Int? {
        let name = project.folded
        let context = [area ?? "", client ?? ""].map(\.folded)
        if name.hasPrefix(needle) {
            return 5
        }
        if name.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
            return 4
        }
        if name.contains(needle) {
            return 3
        }
        if context.contains(where: { $0.contains(needle) }) {
            return 2
        }
        var remaining = Substring(needle)
        for character in ([name] + context).joined(separator: " ") where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty {
                return 1
            }
        }
        return nil
    }
}
