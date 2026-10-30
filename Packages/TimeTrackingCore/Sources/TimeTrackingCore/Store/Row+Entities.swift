// Row coding: entities to and from rows of the schema (spec_data_and_sync.md §2.1).
// Timestamps are Unix seconds except `modified_at` (milliseconds); booleans 0/1.

import Foundation
import GRDB

enum Time {
    static func seconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    static func seconds(optional date: Date?) -> Int64? {
        date.map { seconds($0) }
    }

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    static func date(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func date(optional seconds: Int64?) -> Date? {
        seconds.map { date($0) }
    }

    static func date(millis: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    /// `date` truncated to whole seconds.
    static func whole(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// `date` truncated to whole milliseconds.
    static func wholeMillis(_ instant: Date) -> Date {
        date(millis: millis(instant))
    }
}

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

extension SuggestionFeedback {
    init(row: Row) {
        self.init(
            id: row.requiredID("id"),
            recordedAt: Time.date(row["recorded_at"] as Int64),
            queryStart: Time.date(row["query_start"] as Int64),
            queryEnd: Time.date(row["query_end"] as Int64),
            queryItems: row["query_items"],
            source: Source(rawValue: row["source"]) ?? .block,
            blockStart: Time.date(optional: row["block_start"] as Int64?),
            blockDevice: row["block_device"],
            proposedProjectID: row.uuid("proposed_project_id"),
            proposedTask: row["proposed_task"],
            confidence: row["confidence"],
            outcome: Outcome(rawValue: row["outcome"]) ?? .skipped,
            chosenProjectID: row.uuid("chosen_project_id"),
            chosenTask: row["chosen_task"],
            entryID: row.uuid("entry_id"),
            createdAt: Time.date(row["created_at"] as Int64),
            modifiedAt: Time.date(millis: row["modified_at"]),
            deletedAt: Time.date(optional: row["deleted_at"] as Int64?)
        )
    }

    func save(_ database: Database) throws {
        try database.execute(
            sql: """
            INSERT OR REPLACE INTO suggestion_feedback (id, recorded_at, query_start, query_end, query_items, source,
              block_start, block_device, proposed_project_id, proposed_task, confidence, outcome,
              chosen_project_id, chosen_task, entry_id, created_at, modified_at, deleted_at, ck_system_fields)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
              (SELECT ck_system_fields FROM suggestion_feedback WHERE id = ?))
            """,
            arguments: [
                id.rawValue, Time.seconds(recordedAt), Time.seconds(queryStart), Time.seconds(queryEnd), queryItems,
                source.rawValue, Time.seconds(optional: blockStart), blockDevice, proposedProjectID?.rawValue, proposedTask,
                confidence, outcome.rawValue, chosenProjectID?.rawValue, chosenTask, entryID?.rawValue,
                Time.seconds(createdAt), Time.millis(modifiedAt), Time.seconds(optional: deletedAt), id.rawValue,
            ]
        )
    }
}
