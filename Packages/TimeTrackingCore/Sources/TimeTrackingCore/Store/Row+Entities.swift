// Row coding: entities to and from rows of the schema (spec_data_and_sync.md §2.1).
// Timestamps are Unix seconds except `modified_at` (milliseconds); booleans 0/1.

import Foundation
import GRDB

extension Row {
    func uuid<Entity>(_ column: String) -> Identifier<Entity>? {
        (self[column] as String?).flatMap { Identifier($0) }
    }

    func requiredID<Entity>(_ column: String) -> Identifier<Entity> {
        uuid(column) ?? Identifier(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }
}

extension Client {
    init(row: Row) {
        self.init(
            id: row.requiredID("id"),
            name: row["name"],
            createdAt: Time.date(row["created_at"] as Int64),
            modifiedAt: Time.date(millis: row["modified_at"]),
            deletedAt: Time.date(optional: row["deleted_at"] as Int64?)
        )
    }

    func save(_ database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO client (id, name, created_at, modified_at, deleted_at) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, created_at = excluded.created_at,
              modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
            """,
            arguments: [id.rawValue, name, Time.seconds(createdAt), Time.millis(modifiedAt), Time.seconds(optional: deletedAt)]
        )
    }
}

extension Area {
    init(row: Row) {
        self.init(
            id: row.requiredID("id"),
            clientID: row.requiredID("client_id"),
            name: row["name"],
            isGeneral: row["general"],
            color: row["color"],
            sortOrder: row["sort_order"],
            isRetired: row["retired"],
            createdAt: Time.date(row["created_at"] as Int64),
            modifiedAt: Time.date(millis: row["modified_at"]),
            deletedAt: Time.date(optional: row["deleted_at"] as Int64?)
        )
    }

    func save(_ database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO area (id, client_id, name, general, color, sort_order, retired, created_at, modified_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET client_id = excluded.client_id, name = excluded.name,
              general = excluded.general, color = excluded.color, sort_order = excluded.sort_order,
              retired = excluded.retired, created_at = excluded.created_at,
              modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
            """,
            arguments: [
                id.rawValue, clientID.rawValue, name, isGeneral, color, sortOrder, isRetired,
                Time.seconds(createdAt), Time.millis(modifiedAt), Time.seconds(optional: deletedAt),
            ]
        )
    }
}

extension Project {
    init(row: Row) {
        self.init(
            id: row.requiredID("id"),
            areaID: row.requiredID("area_id"),
            name: row["name"],
            isArchived: row["archived"],
            archivedAt: Time.date(optional: row["archived_at"] as Int64?),
            createdAt: Time.date(row["created_at"] as Int64),
            modifiedAt: Time.date(millis: row["modified_at"]),
            deletedAt: Time.date(optional: row["deleted_at"] as Int64?)
        )
    }

    func save(_ database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO project (id, area_id, name, archived, archived_at, created_at, modified_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET area_id = excluded.area_id, name = excluded.name,
              archived = excluded.archived, archived_at = excluded.archived_at, created_at = excluded.created_at,
              modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
            """,
            arguments: [
                id.rawValue, areaID.rawValue, name, isArchived, Time.seconds(optional: archivedAt),
                Time.seconds(createdAt), Time.millis(modifiedAt), Time.seconds(optional: deletedAt),
            ]
        )
    }
}

extension TimeEntry {
    /// The columns of `time_entry` in the order `init(row:)` expects, for
    /// queries that join (`e.` prefix).
    static let columns = """
    e.id, e.project_id, e.task, e.start, e."end", e.day, e.time_zone, e.device_id, e.split_root_id,
    e.created_at, e.modified_at, e.deleted_at
    """

    init(row: Row) {
        self.init(
            id: row.requiredID("id"),
            projectID: row.uuid("project_id"),
            task: row["task"],
            start: Time.date(row["start"] as Int64),
            end: Time.date(optional: row["end"] as Int64?),
            timeZone: row["time_zone"],
            deviceID: row.requiredID("device_id"),
            splitRootID: row.uuid("split_root_id"),
            day: TrackingDay(row["day"] as String),
            createdAt: Time.date(row["created_at"] as Int64),
            modifiedAt: Time.date(millis: row["modified_at"]),
            deletedAt: Time.date(optional: row["deleted_at"] as Int64?)
        )
    }

    /// Writes the entry; `day` and `task_key` are computed here.
    func save(_ database: Database) throws {
        let day = TrackingCalendar.day(of: self)
        try database.execute(
            sql: """
            INSERT INTO time_entry (id, project_id, task, task_key, start, "end", day, time_zone, device_id,
              split_root_id, created_at, modified_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET project_id = excluded.project_id, task = excluded.task,
              task_key = excluded.task_key, start = excluded.start, "end" = excluded."end", day = excluded.day,
              time_zone = excluded.time_zone, device_id = excluded.device_id, split_root_id = excluded.split_root_id,
              created_at = excluded.created_at, modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
            """,
            arguments: [
                id.rawValue, projectID?.rawValue, task, task.folded, Time.seconds(start), Time.seconds(optional: end),
                day.description, timeZone, deviceID.rawValue, splitRootID?.rawValue,
                Time.seconds(createdAt), Time.millis(modifiedAt), Time.seconds(optional: deletedAt),
            ]
        )
    }
}

extension Device {
    init(row: Row) {
        self.init(
            id: row.requiredID("id"),
            name: row["name"],
            platform: DevicePlatform(rawValue: row["platform"]) ?? .mac,
            lastSeenAt: Time.date(row["last_seen_at"] as Int64),
            widgetPushToken: row["widget_push_token"],
            createdAt: Time.date(row["created_at"] as Int64),
            modifiedAt: Time.date(millis: row["modified_at"])
        )
    }

    func save(_ database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO device (id, name, platform, last_seen_at, widget_push_token, created_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, platform = excluded.platform,
              last_seen_at = excluded.last_seen_at, widget_push_token = excluded.widget_push_token,
              created_at = excluded.created_at, modified_at = excluded.modified_at
            """,
            arguments: [
                id.rawValue, name, platform.rawValue, Time.seconds(lastSeenAt), widgetPushToken,
                Time.seconds(createdAt), Time.millis(modifiedAt),
            ]
        )
    }
}

extension HealthPeriod {
    init(row: Row) {
        self.init(
            id: row.requiredID("id"),
            kind: Kind(rawValue: row["kind"]) ?? .sleep,
            start: Time.date(row["start"] as Int64),
            end: Time.date(row["end"] as Int64),
            activity: row["activity"],
            distance: row["distance"],
            createdAt: Time.date(row["created_at"] as Int64),
            modifiedAt: Time.date(millis: row["modified_at"]),
            deletedAt: Time.date(optional: row["deleted_at"] as Int64?)
        )
    }

    func save(_ database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO health_period (id, kind, start, "end", activity, distance, created_at, modified_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, start = excluded.start, "end" = excluded."end",
              activity = excluded.activity, distance = excluded.distance,
              created_at = excluded.created_at, modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
            """,
            arguments: [
                id.rawValue, kind.rawValue, Time.seconds(start), Time.seconds(end), activity, distance,
                Time.seconds(createdAt), Time.millis(modifiedAt), Time.seconds(optional: deletedAt),
            ]
        )
    }
}
