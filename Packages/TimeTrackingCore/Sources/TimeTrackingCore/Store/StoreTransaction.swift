// StoreTransaction: one write transaction of the store (spec_data_and_sync.md §2.2, §7.1).

public import Foundation
import GRDB

/// The synchronous write API inside one transaction.
///
/// `TimeStore` wraps every write in a transaction: it opens one, runs the
/// operation on a `StoreTransaction`, runs the invariant pass, appends one
/// outbox row per changed record, commits, and then notifies. Use it
/// directly through `TimeStore.transaction(_:)` to group several writes into
/// one transaction with one pass. A transaction is valid only inside that
/// closure.
public final class StoreTransaction {
    /// The time of the transaction, whole seconds; nothing may be written
    /// after it.
    public let now: Date
    /// The writing device.
    public let deviceID: DeviceID
    /// The writing device's zone, for new entries.
    public let timeZone: TimeZone

    let database: Database
    /// `now` with millisecond precision, the `modifiedAt` of every write.
    let modifiedAt: Date
    /// Records to queue in the outbox, in order of first change.
    private(set) var queued: [SyncRecordRef] = []
    private var queuedSet: Set<SyncRecordRef> = []
    private(set) var changedEntryIDs: Set<EntryID> = []
    private(set) var changedSettings: Set<String> = []
    var structureChanged = false
    var liveStateChanged = false
    var adjustments: [EntryAdjustment] = []
    /// Number of midnight-split pieces created in this transaction.
    var splitPieceCount = 0

    init(database: Database, now: Date, deviceID: DeviceID, timeZone: TimeZone) {
        self.database = database
        self.modifiedAt = Time.wholeMillis(now)
        self.now = Time.whole(now)
        self.deviceID = deviceID
        self.timeZone = timeZone
    }

    // MARK: Bookkeeping

    func markChanged(_ ref: SyncRecordRef, queue: Bool = true) {
        switch ref.type {
        case .timeEntry:
            if let id = EntryID(ref.name) {
                changedEntryIDs.insert(id)
            }
        case .setting:
            changedSettings.insert(ref.name)
        case .client, .area, .project, .device:
            structureChanged = true
        case .liveState:
            liveStateChanged = true
        case .suggestionFeedback:
            break
        }
        if queue, queuedSet.insert(ref).inserted {
            queued.append(ref)
        }
    }

    /// Writes `entry` with `modifiedAt = now` and queues it.
    func write(_ entry: TimeEntry) throws {
        var entry = entry
        entry.modifiedAt = modifiedAt
        entry.day = TrackingCalendar.day(of: entry)
        try entry.save(database)
        markChanged(SyncRecordRef(.timeEntry, entry.id.rawValue))
    }

    func write(_ client: Client) throws {
        var client = client
        client.modifiedAt = modifiedAt
        try client.save(database)
        markChanged(SyncRecordRef(.client, client.id.rawValue))
    }

    func write(_ area: Area) throws {
        var area = area
        area.modifiedAt = modifiedAt
        try area.save(database)
        markChanged(SyncRecordRef(.area, area.id.rawValue))
    }

    func write(_ project: Project) throws {
        var project = project
        project.modifiedAt = modifiedAt
        try project.save(database)
        markChanged(SyncRecordRef(.project, project.id.rawValue))
    }

    /// Appends the outbox rows of every queued record.
    func appendOutboxRows() throws {
        for ref in queued {
            try database.execute(
                sql: "INSERT INTO outbox (record_type, record_id, queued_at) VALUES (?, ?, ?)",
                arguments: [ref.type.rawValue, ref.name, Time.seconds(now)]
            )
        }
    }

    // MARK: Lookups

    func entry(_ id: EntryID, includeDeleted: Bool = false) throws -> TimeEntry? {
        let sql = "SELECT * FROM time_entry WHERE id = ?" + (includeDeleted ? "" : " AND deleted_at IS NULL")
        return try Row.fetchOne(database, sql: sql, arguments: [id.rawValue]).map(TimeEntry.init(row:))
    }

    func liveEntry(_ id: EntryID) throws -> TimeEntry {
        guard let entry = try entry(id) else {
            throw StoreError.unknownID
        }
        return entry
    }

    func runningEntries() throws -> [TimeEntry] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM time_entry INDEXED BY time_entry_running WHERE deleted_at IS NULL AND \"end\" IS NULL ORDER BY start, id"
        ).map(TimeEntry.init(row:))
    }

    func chainEntries(root: EntryID) throws -> [TimeEntry] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM time_entry WHERE deleted_at IS NULL AND (id = ? OR split_root_id = ?) ORDER BY start, id",
            arguments: [root.rawValue, root.rawValue]
        ).map(TimeEntry.init(row:))
    }

    func client(_ id: ClientID, includeDeleted: Bool = false) throws -> Client? {
        let sql = "SELECT * FROM client WHERE id = ?" + (includeDeleted ? "" : " AND deleted_at IS NULL")
        return try Row.fetchOne(database, sql: sql, arguments: [id.rawValue]).map(Client.init(row:))
    }

    func area(_ id: AreaID, includeDeleted: Bool = false) throws -> Area? {
        let sql = "SELECT * FROM area WHERE id = ?" + (includeDeleted ? "" : " AND deleted_at IS NULL")
        return try Row.fetchOne(database, sql: sql, arguments: [id.rawValue]).map(Area.init(row:))
    }

    func project(_ id: ProjectID, includeDeleted: Bool = false) throws -> Project? {
        let sql = "SELECT * FROM project WHERE id = ?" + (includeDeleted ? "" : " AND deleted_at IS NULL")
        return try Row.fetchOne(database, sql: sql, arguments: [id.rawValue]).map(Project.init(row:))
    }

    func liveAreas(of client: ClientID) throws -> [Area] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM area WHERE client_id = ? AND deleted_at IS NULL ORDER BY sort_order, name",
            arguments: [client.rawValue]
        ).map(Area.init(row:))
    }

    /// Live projects in the live areas of `client`.
    func liveProjects(of client: ClientID) throws -> [Project] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT p.* FROM project p JOIN area a ON a.id = p.area_id
            WHERE a.client_id = ? AND p.deleted_at IS NULL AND a.deleted_at IS NULL
            """,
            arguments: [client.rawValue]
        ).map(Project.init(row:))
    }

    func liveProjects(in area: AreaID) throws -> [Project] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM project WHERE area_id = ? AND deleted_at IS NULL",
            arguments: [area.rawValue]
        ).map(Project.init(row:))
    }

    func liveAreaColors() throws -> [AreaColor] {
        try String.fetchAll(database, sql: "SELECT color FROM area WHERE deleted_at IS NULL")
            .compactMap { try? AreaColor($0) }
    }
}
