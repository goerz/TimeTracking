// Entry queries (data_and_sync.md §7.2).

public import Foundation
import GRDB

extension TimeStore: TimeStoreReading {
    public func runningEntry() throws -> TimeEntry? {
        try read { database in
            // The partial index holds only running entries; left alone, the
            // planner walks the start index for the ORDER BY (§7.5: under 1 ms).
            try Row.fetchOne(
                database,
                sql: "SELECT * FROM time_entry INDEXED BY time_entry_running WHERE deleted_at IS NULL AND \"end\" IS NULL "
                    + "ORDER BY start DESC, id DESC LIMIT 1"
            ).map(TimeEntry.init(row:))
        }
    }

    public func entry(_ id: EntryID) throws -> TimeEntry? {
        try read { try StoreQueries.entry(id, includeDeleted: false, in: $0) }
    }

    /// An entry, also a tombstone.
    public func entry(_ id: EntryID, includeDeleted: Bool) throws -> TimeEntry? {
        try read { try StoreQueries.entry(id, includeDeleted: includeDeleted, in: $0) }
    }

    public func entries(in interval: DateInterval, includeDeleted: Bool = false) throws -> [TimeEntry] {
        let start = Time.seconds(interval.start)
        return try fetchEntries(
            where: "start < ? AND (COALESCE(\"end\", ?) > ? OR start >= ?)" + (includeDeleted ? "" : " AND deleted_at IS NULL"),
            [Time.seconds(interval.end), Time.seconds(clock.now), start, start]
        )
    }

    public func entries(on day: TrackingDay) throws -> [TimeEntry] {
        try fetchEntries(where: "day = ? AND deleted_at IS NULL", [day.description])
    }

    /// The live entries that can have a piece on `days`, by start. An entry
    /// can start any number of days before them, so this is interval
    /// overlap, not a filter on `day`; the caller keeps the pieces it wants.
    public func entries(reaching days: ClosedRange<TrackingDay>, in calendar: TrackingCalendar) throws -> [TimeEntry] {
        let reach = calendar.reach(of: days)
        return try fetchEntries(
            where: "start < ? AND COALESCE(\"end\", ?) > ? AND deleted_at IS NULL",
            [Time.seconds(reach.end), Time.seconds(clock.now), Time.seconds(reach.start)]
        )
    }

    public func days(ending: TrackingDay, count: Int) throws -> [DayGroup] {
        guard count > 0 else {
            return []
        }
        let first = ending.adding(days: 1 - count)
        let now = clock.now
        let calendar = displayCalendar(timeZone: timeZone())
        let pieces = try entries(reaching: first ... ending, in: calendar).flatMap { calendar.pieces(of: $0, at: now) }
        let byDay = Dictionary(grouping: pieces, by: \.day)
        return (0 ..< count).map { offset in
            let day = ending.adding(days: -offset)
            let entries = (byDay[day] ?? []).sorted { ($0.start, $0.id) > ($1.start, $1.id) }
            return DayGroup(
                day: day,
                entries: entries,
                totalSeconds: entries.reduce(0) { $0 + $1.seconds(at: now) },
                includesRunning: entries.contains(where: \.isRunning)
            )
        }
    }

    public func recentEntries(before: Date?, limit: Int) throws -> [TimeEntry] {
        let before = before.map { Time.seconds($0) } ?? Int64.max
        return try fetchEntries(
            where: "start < ? AND deleted_at IS NULL",
            [before],
            order: "start DESC, id DESC LIMIT \(max(limit, 0))"
        )
    }

    public func lastStoppedEntry(excluding: EntryID?) throws -> TimeEntry? {
        try fetchEntries(
            where: "\"end\" IS NOT NULL AND deleted_at IS NULL AND id != ?",
            [excluding?.rawValue ?? ""],
            order: "\"end\" DESC, start DESC LIMIT 1"
        ).first
    }

    public func recentProjects(limit: Int) throws -> [ProjectID] {
        try read { database in
            try String.fetchAll(
                database,
                sql: """
                SELECT e.project_id FROM time_entry e JOIN project p ON p.id = e.project_id
                WHERE e.deleted_at IS NULL AND p.deleted_at IS NULL AND p.archived = 0
                GROUP BY e.project_id ORDER BY MAX(e.start) DESC, e.project_id LIMIT ?
                """,
                arguments: [limit]
            ).compactMap { ProjectID($0) }
        }
    }

    public func overlaps(for draft: EntryDraft, excluding: EntryID?) throws -> [TimeEntry] {
        let now = clock.now
        let end = draft.end ?? now
        return try entries(in: DateInterval(start: draft.start, end: max(end, draft.start)))
            .filter { $0.id != excluding && $0.start < end && ($0.end ?? now) > draft.start }
    }

    public func overlappingEntries(in interval: DateInterval) throws -> [(TimeEntry, TimeEntry)] {
        let now = clock.now
        let entries = try entries(in: interval)
        var pairs: [(TimeEntry, TimeEntry)] = []
        for (index, first) in entries.enumerated() {
            for second in entries[(index + 1)...] {
                if second.start >= (first.end ?? now) {
                    continue
                }
                if second.start < (first.end ?? now), (second.end ?? now) > first.start {
                    pairs.append((first, second))
                }
            }
        }
        return pairs
    }

    public func distinctTasks(projectID: ProjectID?, prefix: String, limit: Int) throws -> [TaskSuggestion] {
        let projectClause = projectID == nil ? "e.project_id IS NULL" : "e.project_id = ?"
        var arguments: [any DatabaseValueConvertible] = projectID.map { [$0.rawValue] } ?? []
        arguments.append(Self.likePattern(prefix: prefix.folded))
        arguments.append(limit)
        return try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT e.task_key, MAX(e.start) AS last_used, COUNT(*) AS uses,
                  (SELECT task FROM time_entry t WHERE t.task_key = e.task_key AND t.deleted_at IS NULL
                     AND t.project_id IS e.project_id ORDER BY t.start DESC LIMIT 1) AS task
                FROM time_entry e LEFT JOIN project p ON p.id = e.project_id
                WHERE e.deleted_at IS NULL AND \(projectClause) AND e.task_key != '' AND e.task_key LIKE ? ESCAPE '\\'
                  AND (p.id IS NULL OR p.archived = 0)
                GROUP BY e.task_key ORDER BY last_used DESC, e.task_key LIMIT ?
                """,
                arguments: StatementArguments(arguments)
            ).map { row in
                TaskSuggestion(
                    task: row["task"],
                    projectID: projectID,
                    lastUsed: Time.date(row["last_used"] as Int64),
                    useCount: row["uses"]
                )
            }
        }
    }

    public func projectsByTask(matching text: String, since: Date) throws -> [ProjectID] {
        let pattern = "%" + Self.escapeLike(text.folded) + "%"
        return try read { database in
            try String.fetchAll(
                database,
                sql: """
                SELECT e.project_id FROM time_entry e JOIN project p ON p.id = e.project_id
                WHERE e.deleted_at IS NULL AND p.deleted_at IS NULL AND p.archived = 0
                  AND e.start >= ? AND e.task_key LIKE ? ESCAPE '\\'
                GROUP BY e.project_id ORDER BY MAX(e.start) DESC
                """,
                arguments: [Time.seconds(since), pattern]
            ).compactMap { ProjectID($0) }
        }
    }

    public func recentCombinations(limit: Int) throws -> [(ProjectID?, String)] {
        try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT e.project_id, e.task FROM time_entry e LEFT JOIN project p ON p.id = e.project_id
                WHERE e.deleted_at IS NULL AND (p.id IS NULL OR (p.archived = 0 AND p.deleted_at IS NULL))
                GROUP BY e.project_id, e.task_key ORDER BY MAX(e.start) DESC LIMIT ?
                """,
                arguments: [limit]
            ).map { row in (row.uuid("project_id"), row["task"]) }
        }
    }

    // MARK: Helpers

    func fetchEntries(
        where clause: String,
        _ arguments: [any DatabaseValueConvertible],
        order: String = "start, id"
    ) throws -> [TimeEntry] {
        try read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT * FROM time_entry WHERE \(clause) ORDER BY \(order)",
                arguments: StatementArguments(arguments)
            ).map(TimeEntry.init(row:))
        }
    }

    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    static func likePattern(prefix: String) -> String {
        escapeLike(prefix) + "%"
    }
}
