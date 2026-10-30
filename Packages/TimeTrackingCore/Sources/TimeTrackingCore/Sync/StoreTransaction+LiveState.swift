// The live_state row: the running snapshot written in every write
// transaction, this Mac's activity, and the merge of a remote copy
// (spec_data_and_sync.md §4.1, §4.2).

import Foundation
import GRDB

extension StoreTransaction {
    static let liveStateRef = SyncRecordRef(.liveState, "LiveState")

    /// The local row as a `LiveState` (empty without a row).
    func liveState() throws -> LiveState {
        guard let row = try Row.fetchOne(database, sql: "SELECT * FROM live_state WHERE id = 1") else {
            return LiveState()
        }
        return LiveState(
            running: LiveState.running(json: row["running"]),
            changedAt: (row["changed_at"] as Int64?).map { Time.date(millis: $0) },
            activity: LiveState.activity(json: row["activity"])
        )
    }

    /// The row as a sync record, or `nil` without a row.
    func liveStateRecord() throws -> SyncRecord? {
        guard let row = try Row.fetchOne(database, sql: "SELECT * FROM live_state WHERE id = 1") else {
            return nil
        }
        var fields: [String: SyncValue] = ["activity": .string(row["activity"])]
        if let running = row["running"] as String? {
            fields["running"] = .string(running)
        }
        if let changed = row["changed_at"] as Int64? {
            fields["changedAt"] = .date(Time.date(millis: changed))
        }
        return SyncRecord(ref: Self.liveStateRef, fields: fields, systemFields: row["ck_system_fields"])
    }

    /// Writes the row; `queue` puts `LiveState` in the outbox.
    func writeLiveState(_ state: LiveState, queue: Bool) throws {
        try database.execute(
            sql: """
            INSERT INTO live_state (id, running, changed_at, activity) VALUES (1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET running = excluded.running, changed_at = excluded.changed_at,
              activity = excluded.activity
            """,
            arguments: [
                LiveState.runningJSON(state.running),
                state.changedAt.map { Time.millis($0) },
                LiveState.activityJSON(state.activity),
            ]
        )
        markChanged(Self.liveStateRef, queue: queue)
    }

    func setLiveStateSystemFields(_ data: Data?) throws {
        try database.execute(sql: "UPDATE live_state SET ck_system_fields = ? WHERE id = 1", arguments: [data])
    }

    /// The running part computed from the store: the running entry with its
    /// project, client, area color, and chain start.
    func runningSnapshot() throws -> (running: LiveState.Running?, projectMissing: Bool) {
        guard let entry = try runningEntries().last else {
            return (nil, false)
        }
        let project = try entry.projectID.flatMap { try self.project($0, includeDeleted: true) }
        let area = try project.flatMap { try self.area($0.areaID, includeDeleted: true) }
        let client = try area.flatMap { try self.client($0.clientID, includeDeleted: true) }
        let running = try LiveState.Running(
            entryID: entry.id,
            projectID: entry.projectID,
            task: entry.task,
            projectName: project?.name,
            clientName: client?.name,
            areaColor: area?.color,
            chainStart: chainStart(root: entry.rootID) ?? entry.start
        )
        return (running, entry.projectID != nil && project == nil)
    }

    /// After the pass of every write transaction (§4.2): writes the running
    /// snapshot with `changedAt = now` and queues `LiveState` when it
    /// differs from the row. A row naming the same entry and project is kept
    /// while that project has not arrived yet, so a receiver never replaces
    /// a complete snapshot with a partial one.
    func updateLiveStateSnapshot() throws {
        let (running, projectMissing) = try runningSnapshot()
        var state = try liveState()
        guard LiveState.runningJSON(running) != LiveState.runningJSON(state.running) else {
            return
        }
        if projectMissing, let current = state.running, current.entryID == running?.entryID,
           current.projectID == running?.projectID
        {
            return
        }
        state.running = running
        state.changedAt = modifiedAt
        try writeLiveState(state, queue: true)
    }

    /// Sets (or with `nil` removes) one Mac's activity and queues `LiveState`.
    public func setLiveActivity(_ activity: LiveState.MacActivity?, for device: DeviceID) throws {
        var state = try liveState()
        guard state.activity[device.rawValue] != activity else {
            return
        }
        state.activity[device.rawValue] = activity
        try writeLiveState(state, queue: true)
    }

    /// A fetched or conflicting `LiveState` (§4.1): the merge goes into the
    /// row with the server's system fields; it is queued only when the local
    /// side contributed something the server lacks.
    func applyRemoteLiveState(_ remote: SyncRecord) throws {
        let theirs = LiveState(
            running: LiveState.running(json: remote["running"]?.string),
            changedAt: remote["changedAt"]?.date.map { Time.wholeMillis($0) },
            activity: LiveState.activity(json: remote["activity"]?.string)
        )
        let mine = try liveState()
        let merged = mine.merged(with: theirs)
        let differsFromServer = merged != theirs
        if merged != mine {
            try writeLiveState(merged, queue: differsFromServer)
        } else if differsFromServer {
            markChanged(Self.liveStateRef)
        }
        if try Row.fetchOne(database, sql: "SELECT id FROM live_state WHERE id = 1") == nil {
            try writeLiveState(merged, queue: differsFromServer)
        }
        try setLiveStateSystemFields(remote.systemFields)
    }
}
