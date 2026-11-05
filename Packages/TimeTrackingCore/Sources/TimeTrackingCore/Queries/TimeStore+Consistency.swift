// consistencyIssues(): integrity is reported, never repaired (data_and_sync.md §1.4, §3.2, §3.3).

import Foundation
import GRDB

extension TimeStore {
    public func consistencyIssues() throws -> [ConsistencyIssue] {
        let now = clock.now
        return try read { database in
            var issues = try Self.danglingReferences(in: database, now: now)
            try issues.append(contentsOf: Self.duplicateNames(in: database))
            return issues
        }
    }

    /// Running entries ahead of the clock and references to missing records.
    static func danglingReferences(in database: Database, now: Date) throws -> [ConsistencyIssue] {
        var issues: [ConsistencyIssue] = []
        let ahead = Time.seconds(now) + 300
        for row in try Row.fetchAll(
            database,
            sql: "SELECT id, start FROM time_entry WHERE deleted_at IS NULL AND \"end\" IS NULL AND start > ?",
            arguments: [ahead]
        ) {
            issues.append(.runningInFuture(row.requiredID("id"), start: Time.date(row["start"] as Int64)))
        }
        for row in try Row.fetchAll(
            database,
            sql: """
            SELECT e.id, e.project_id FROM time_entry e LEFT JOIN project p ON p.id = e.project_id AND p.deleted_at IS NULL
            WHERE e.deleted_at IS NULL AND e.project_id IS NOT NULL AND p.id IS NULL ORDER BY e.start
            """
        ) {
            issues.append(.unknownProject(row.requiredID("id"), projectID: row.requiredID("project_id")))
        }
        for row in try Row.fetchAll(
            database,
            sql: """
            SELECT p.id, p.area_id FROM project p LEFT JOIN area a ON a.id = p.area_id AND a.deleted_at IS NULL
            WHERE p.deleted_at IS NULL AND a.id IS NULL ORDER BY p.name
            """
        ) {
            issues.append(.projectWithoutArea(row.requiredID("id"), areaID: row.requiredID("area_id")))
        }
        for row in try Row.fetchAll(
            database,
            sql: """
            SELECT a.id, a.client_id FROM area a LEFT JOIN client c ON c.id = a.client_id AND c.deleted_at IS NULL
            WHERE a.deleted_at IS NULL AND c.id IS NULL ORDER BY a.name
            """
        ) {
            issues.append(.areaWithoutClient(row.requiredID("id"), clientID: row.requiredID("client_id")))
        }
        return issues
    }

    /// Live clients, areas within a client, and projects within a client
    /// sharing a folded name.
    static func duplicateNames(in database: Database) throws -> [ConsistencyIssue] {
        let scopes: [(ConsistencyIssue.Kind, String)] = [
            (.client, "SELECT id, name, '' AS scope FROM client WHERE deleted_at IS NULL"),
            (.area, "SELECT id, name, client_id AS scope FROM area WHERE deleted_at IS NULL"),
            (.project, """
            SELECT p.id, p.name, a.client_id AS scope FROM project p JOIN area a ON a.id = p.area_id
            WHERE p.deleted_at IS NULL
            """),
        ]
        var issues: [ConsistencyIssue] = []
        for (kind, sql) in scopes {
            let rows = try Row.fetchAll(database, sql: sql)
            let groups = Dictionary(grouping: rows) { row in "\(row["scope"] as String)\u{1F}\((row["name"] as String).folded)" }
            for (_, group) in groups.sorted(by: { $0.key < $1.key }) where group.count > 1 {
                let ids = group.compactMap { UUID(uuidString: $0["id"]) }.sorted { $0.uuidString < $1.uuidString }
                issues.append(.duplicateName(kind, name: group[0]["name"], ids: ids))
            }
        }
        return issues
    }
}
