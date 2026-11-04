// The store's side of sync: the outbox, applying fetched batches, conflicts
// (spec_data_and_sync.md §2.2, §3.1, §3.2). Only the app's sync engine calls
// these; the command-line tool only appends outbox rows.

public import Foundation
import GRDB

/// Records drained from the outbox for one send.
public struct PendingChanges: Sendable, Hashable {
    /// Current rows of the queued records.
    public var records: [SyncRecord]
    /// Queued records whose rows no longer exist (hard deletions).
    public var deletions: [SyncRecordRef]
    /// The last outbox sequence number covered.
    public var throughSequence: Int64

    public var isEmpty: Bool {
        records.isEmpty && deletions.isEmpty
    }
}

extension TimeStore {
    /// The number of outbox rows.
    public func outboxCount() throws -> Int {
        try read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox") ?? 0 }
    }

    /// The queued records, each once, from the oldest outbox rows.
    public func pendingChanges(limit: Int = 400) throws -> PendingChanges {
        guard let writer else {
            throw StoreError.readOnly
        }
        return try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT seq, record_type, record_id FROM outbox ORDER BY seq LIMIT ?",
                arguments: [limit]
            )
            let transaction = StoreTransaction(database: database, now: clock.now, deviceID: deviceID, timeZone: timeZone())
            var seen: Set<SyncRecordRef> = []
            var pending = PendingChanges(records: [], deletions: [], throughSequence: 0)
            for row in rows {
                pending.throughSequence = row["seq"]
                guard let type = SyncRecordType(rawValue: row["record_type"]) else {
                    continue
                }
                let ref = SyncRecordRef(type, row["record_id"])
                guard seen.insert(ref).inserted else {
                    continue
                }
                if let record = try transaction.syncRecord(ref) {
                    pending.records.append(record)
                } else if type != .liveState {
                    pending.deletions.append(ref)
                }
            }
            return pending
        }
    }

    /// After a send: removes the covered outbox rows and stores the system
    /// fields the server returned for the saved records.
    /// Returns `.saved` when the server confirmed this device's `LiveState`.
    @discardableResult
    public func confirmSent(_ pending: PendingChanges, saved: [SyncRecord]) throws -> LiveStateSyncEvent? {
        let (state, _) = try perform { transaction -> LiveState? in
            try transaction.database.execute(sql: "DELETE FROM outbox WHERE seq <= ?", arguments: [pending.throughSequence])
            for record in saved {
                try transaction.setSystemFields(record.ref, record.systemFields)
            }
            return try saved.contains { $0.ref.type == .liveState } ? transaction.liveState() : nil
        }
        return state.map { .saved($0) }
    }

    /// Applies a fetched batch in one transaction followed by the invariant
    /// pass. Returns `.fetched` when the batch held `LiveState`.
    @discardableResult
    public func applyFetched(_ records: [SyncRecord], deletions: [SyncRecordRef]) throws -> LiveStateSyncEvent? {
        try write { transaction -> LiveStateSyncEvent? in
            let before = try transaction.liveState()
            for record in records {
                try transaction.applyRemote(record)
            }
            for ref in deletions {
                try transaction.applyRemoteDeletion(ref)
            }
            guard records.contains(where: { $0.ref.type == .liveState }) else {
                return nil
            }
            let after = try transaction.liveState()
            let changed = LiveState.runningJSON(after.running) != LiveState.runningJSON(before.running)
            return .fetched(after, runningChanged: changed)
        }
    }

    /// A `serverRecordChanged` rejection: merge with the server's copy
    /// (§3.2); a winning local copy is re-queued with the server's system
    /// fields, so the next send succeeds.
    public func resolveConflict(server: SyncRecord) throws {
        try write { transaction in
            try transaction.applyRemote(server)
        }
    }

    /// An `unknownItem` rejection: the next send saves the record without
    /// system fields.
    public func requeueWithoutSystemFields(_ refs: [SyncRecordRef]) throws {
        try write { transaction in
            for ref in refs {
                try transaction.setSystemFields(ref, nil)
                transaction.queue(ref)
            }
        }
    }

    /// The record named `name` (a CloudKit record name), from the live and
    /// tombstoned rows or the purged ids; `nil` when the store never had it.
    public func recordRef(named name: String) throws -> SyncRecordRef? {
        if name == StoreTransaction.liveStateRef.name {
            return StoreTransaction.liveStateRef
        }
        return try read { database in
            for type in SyncRecordType.allCases {
                guard let (table, key) = StoreTransaction.table(of: type) else {
                    continue
                }
                if try Bool.fetchOne(database, sql: "SELECT 1 FROM \(table) WHERE \(key) = ?", arguments: [name]) != nil {
                    return SyncRecordRef(type, name)
                }
            }
            let purged = try String.fetchOne(database, sql: "SELECT record_type FROM purged_record WHERE record_id = ?", arguments: [name])
            return purged.flatMap(SyncRecordType.init(rawValue:)).map { SyncRecordRef($0, name) }
        }
    }

    /// The newest outbox sequence number (0 for an empty outbox).
    public func outboxMaxSequence() throws -> Int64 {
        try read { try Int64.fetchOne($0, sql: "SELECT MAX(seq) FROM outbox") ?? 0 }
    }

    /// The outbox's highest sequence and the current records of `refs`, read
    /// in one transaction, so no write can fall between the two: a batch
    /// confirmed up to that sequence holds every change below it.
    public func syncSnapshot(_ refs: [SyncRecordRef]) throws -> (sequence: Int64, records: [SyncRecordRef: SyncRecord]) {
        try read { database in
            let sequence = try Int64.fetchOne(database, sql: "SELECT MAX(seq) FROM outbox") ?? 0
            let transaction = StoreTransaction(database: database, now: clock.now, deviceID: deviceID, timeZone: timeZone())
            var records: [SyncRecordRef: SyncRecord] = [:]
            for ref in refs {
                records[ref] = try transaction.syncRecord(ref)
            }
            return (sequence, records)
        }
    }

    /// The current record of `ref` with its system fields, or `nil` when the
    /// row no longer exists (the engine builds its batches from these).
    public func syncRecord(_ ref: SyncRecordRef) throws -> SyncRecord? {
        try read { database in
            try StoreTransaction(database: database, now: clock.now, deviceID: deviceID, timeZone: timeZone()).syncRecord(ref)
        }
    }

    /// After the engine's send: removes the outbox rows of each ref up to
    /// the sequence number its batch was built at, and stores the saved
    /// records' system fields. Returns `.saved` for a confirmed `LiveState`.
    @discardableResult
    public func confirmSent(_ through: [SyncRecordRef: Int64], saved: [SyncRecord]) throws -> LiveStateSyncEvent? {
        let (state, _) = try perform { transaction -> LiveState? in
            for (ref, sequence) in through {
                try transaction.database.execute(
                    sql: "DELETE FROM outbox WHERE record_type = ? AND record_id = ? AND seq <= ?",
                    arguments: [ref.type.rawValue, ref.name, sequence]
                )
            }
            for record in saved {
                try transaction.setSystemFields(record.ref, record.systemFields)
            }
            return try saved.contains { $0.ref.type == .liveState } ? transaction.liveState() : nil
        }
        return state.map { .saved($0) }
    }

    /// A switch to another iCloud account, after confirmation: the store
    /// becomes empty (the meta table and the store id stay).
    public func resetForAccountSwitch() throws {
        _ = try perform { transaction in
            for table in [
                "client", "area", "project", "time_entry", "setting", "device", "live_state", "health_period",
                "outbox", "sync_state", "purged_record",
            ] {
                try transaction.database.execute(sql: "DELETE FROM \(table)")
            }
        }
        notifier?.post()
        externalChange()
        broadcaster.yield(.liveState)
    }

    /// Records the server did not save for a transient reason: queued again unchanged.
    public func requeue(_ refs: [SyncRecordRef]) throws {
        try write { transaction in
            for ref in refs {
                transaction.queue(ref)
            }
        }
    }

    /// A `zoneNotFound` error: forget every system field and queue every
    /// live record and tombstone.
    public func requeueAll() throws {
        try write { transaction in
            for type in SyncRecordType.allCases {
                guard let (table, key) = StoreTransaction.table(of: type) else {
                    continue
                }
                try transaction.database.execute(sql: "UPDATE \(table) SET ck_system_fields = NULL")
                for name in try String.fetchAll(transaction.database, sql: "SELECT \(key) FROM \(table) ORDER BY \(key)") {
                    transaction.queue(SyncRecordRef(type, name))
                }
            }
            if try transaction.liveStateRecord() != nil {
                try transaction.setLiveStateSystemFields(nil)
                transaction.queue(StoreTransaction.liveStateRef)
            }
        }
    }

    /// A value of the sync engine's private state (`sync_state`).
    public func syncState(_ key: String) throws -> Data? {
        try read { try Data.fetchOne($0, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [key]) }
    }

    public func setSyncState(_ key: String, _ value: Data?) throws {
        _ = try perform { transaction in
            if let value {
                try transaction.database.execute(
                    sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)",
                    arguments: [key, value]
                )
            } else {
                try transaction.database.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [key])
            }
        }
    }
}
