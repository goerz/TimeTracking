// Records of the store's rows and applying remote records (spec_data_and_sync.md §3.1, §3.2).

import Foundation
import GRDB

extension StoreTransaction {
    /// The current record of a row with its system fields; `nil` when the
    /// row does not exist (a hard deletion).
    func syncRecord(_ ref: SyncRecordRef) throws -> SyncRecord? {
        guard let (table, key) = Self.table(of: ref.type),
              let row = try Row.fetchOne(database, sql: "SELECT * FROM \(table) WHERE \(key) = ?", arguments: [ref.name])
        else {
            return nil
        }
        var record: SyncRecord = switch ref.type {
        case .client: Client(row: row).syncRecord
        case .area: Area(row: row).syncRecord
        case .project: Project(row: row).syncRecord
        case .timeEntry: TimeEntry(row: row).syncRecord
        case .device: Device(row: row).syncRecord
        case .suggestionFeedback: SuggestionFeedback(row: row).syncRecord
        case .setting, .liveState: Self.settingRecord(ref, row)
        }
        record.systemFields = row["ck_system_fields"]
        return record
    }

    private static func settingRecord(_ ref: SyncRecordRef, _ row: Row) -> SyncRecord {
        var fields: [String: SyncValue] = [
            "value": .string(row["value"]),
            "modifiedAt": .date(Time.date(millis: row["modified_at"])),
        ]
        if let deleted = row["deleted_at"] as Int64? {
            fields["deletedAt"] = .date(Time.date(deleted))
        }
        return SyncRecord(ref: ref, fields: fields)
    }

    func setSystemFields(_ ref: SyncRecordRef, _ data: Data?) throws {
        guard let (table, key) = Self.table(of: ref.type) else {
            return
        }
        try database.execute(sql: "UPDATE \(table) SET ck_system_fields = ? WHERE \(key) = ?", arguments: [data, ref.name])
    }

    func queue(_ ref: SyncRecordRef) {
        markChanged(ref)
    }

    /// Applies a fetched or conflicting server record by the rules of §3.2:
    /// the later copy wins entirely; `activity.contextColors` merges as a
    /// union. Writes no outbox row for the server's state; a local copy that
    /// wins keeps its data, takes the server's system fields, and is queued.
    func applyRemote(_ remote: SyncRecord) throws {
        guard remote.ref.type != .liveState else {
            return
        }
        let local = try syncRecord(remote.ref)
        if remote.ref.type == .setting, remote.ref.name == SettingMerge.contextColorsKey, let local {
            try mergeContextColors(local: local, remote: remote)
            return
        }
        if let local, !remote.wins(over: local) {
            try setSystemFields(remote.ref, remote.systemFields)
            if local.canonicalFields != remote.canonicalFields {
                queue(remote.ref)
            }
            return
        }
        try writeRemote(remote, replacing: local)
    }

    /// A server hard deletion: a live local record becomes a tombstone at
    /// `now`; a local tombstone is removed.
    func applyRemoteDeletion(_ ref: SyncRecordRef) throws {
        guard let local = try syncRecord(ref) else {
            return
        }
        guard !local.isDeleted, ref.type != .device else {
            try hardDelete(ref, queue: false)
            return
        }
        var tombstone = local
        tombstone["deletedAt"] = .date(now)
        tombstone["modifiedAt"] = .date(modifiedAt)
        tombstone.systemFields = nil
        try writeRemote(tombstone, replacing: local)
    }

    private func writeRemote(_ remote: SyncRecord, replacing local: SyncRecord?) throws {
        let ref = remote.ref
        switch ref.type {
        case .client:
            try Client(record: remote)?.save(database)
        case .area:
            try Area(record: remote)?.save(database)
        case .project:
            try Project(record: remote)?.save(database)
        case .timeEntry:
            guard let entry = TimeEntry(record: remote) else {
                return
            }
            try entry.save(database)
            recordRemoteAdjustment(entry, local: local)
        case .device:
            try Device(record: remote)?.save(database)
        case .suggestionFeedback:
            try SuggestionFeedback(record: remote)?.save(database)
        case .setting:
            try database.execute(
                sql: """
                INSERT INTO setting (key, value, modified_at, deleted_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, modified_at = excluded.modified_at,
                  deleted_at = excluded.deleted_at
                """,
                arguments: [
                    ref.name,
                    remote["value"]?.string ?? "null",
                    remote.modifiedMillis,
                    remote["deletedAt"]?.date.map { Time.seconds($0) },
                ]
            )
        case .liveState:
            return
        }
        try setSystemFields(ref, remote.systemFields)
        markChanged(ref, queue: false)
    }

    private func recordRemoteAdjustment(_ entry: TimeEntry, local: SyncRecord?) {
        guard let local, let before = TimeEntry(record: local), !before.sameContent(as: entry) else {
            return
        }
        let reason: EntryAdjustment.Reason = if !before.isDeleted, entry.isDeleted {
            .deletedRemotely
        } else if before.isDeleted, !entry.isDeleted {
            .restoredRemotely
        } else {
            .replacedByRemoteEdit
        }
        record(reason, before: before, after: entry, causingDevice: nil)
    }

    private func mergeContextColors(local: SyncRecord, remote: SyncRecord) throws {
        func colors(_ record: SyncRecord) -> [String: Int] {
            let json = Data((record["value"]?.string ?? "{}").utf8)
            return (try? JSONDecoder().decode([String: Int].self, from: json)) ?? [:]
        }
        let merged = SettingMerge.mergeContextColors(colors(local), colors(remote))
        if merged == colors(remote) {
            try writeRemote(remote, replacing: local)
            return
        }
        try setSystemFields(remote.ref, remote.systemFields)
        if merged != colors(local) {
            try set(.activityContextColors, merged)
        } else {
            queue(remote.ref)
        }
    }
}
