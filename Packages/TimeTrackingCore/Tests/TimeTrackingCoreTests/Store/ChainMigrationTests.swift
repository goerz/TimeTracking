// Schema version 4: midnight chains become whole entries on every device
// (spec_data_and_sync.md §2.1; §9 items 62 to 65).

import Foundation
import GRDB
import Testing
@testable import TimeTrackingCore

/// A store file at schema version 3, its rows as that version wrote them.
private struct LegacyStore {
    let url: URL
    private let queue: DatabaseQueue
    static let zone = TestTime.berlin
    static let device = DeviceID()

    init(in folder: TemporaryFolder, name: String = "store.sqlite") throws {
        self.url = folder.url.appending(path: name)
        self.queue = try DatabaseQueue(path: url.path)
        try Schema.migrator.migrate(queue, upTo: "v3")
        try queue.write { database in
            try database.execute(sql: "INSERT INTO meta (key, value) VALUES ('schema_version', '3'), ('store_id', 'legacy')")
        }
    }

    /// A row of `time_entry`; times are local to Berlin.
    @discardableResult
    func entry(
        _ id: EntryID = EntryID(),
        root: EntryID? = nil,
        task: String = "",
        from start: String,
        to end: String?,
        modified: Int64 = 1000,
        deleted: Bool = false
    ) throws -> EntryID {
        let begin = try TestTime.local(start, in: Self.zone)
        try queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO time_entry (id, task, task_key, start, "end", day, time_zone, device_id, split_root_id,
                  created_at, modified_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id.rawValue, task, task.lowercased(), Int64(begin.timeIntervalSince1970),
                    end.map { try Int64(TestTime.local($0, in: Self.zone).timeIntervalSince1970) },
                    String(start.prefix(10)), Self.zone.identifier, Self.device.rawValue, root?.rawValue,
                    Int64(begin.timeIntervalSince1970), modified, deleted ? 1 : nil,
                ]
            )
        }
        return id
    }

    func liveState(_ json: String, changedAt: Int64) throws {
        try queue.write { database in
            try database.execute(sql: "INSERT INTO live_state (id, running, changed_at) VALUES (1, ?, ?)", arguments: [json, changedAt])
        }
    }

    /// The merge alone, as the migration runs it.
    func mergeChains() throws {
        try queue.write { try Schema.mergeChains(in: $0) }
    }

    func rows() throws -> [Row] {
        try queue.read { try Row.fetchAll($0, sql: "SELECT id, \"end\", modified_at, deleted_at FROM time_entry ORDER BY id") }
    }

    func outboxCount() throws -> Int {
        try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox") ?? 0 }
    }

    /// Migrates the file by opening it.
    func open(clock: ManualClock, device: DeviceID = Self.device) async throws -> TimeStore {
        try await TimeStore.open(.init(location: .file(url), clock: clock, deviceID: device, timeZone: { Self.zone }))
    }
}

struct ChainMigrationTests {
    private func clock() throws -> ManualClock {
        try ManualClock(TestTime.local("2026-03-10T12:00", in: LegacyStore.zone))
    }

    private func date(_ text: String) throws -> Date {
        try TestTime.local(text, in: LegacyStore.zone)
    }

    @Test(
        "DATA-62 a store at schema 3 migrates: a chain becomes its earliest piece with the last end and its task, later pieces tombstones"
    )
    func mergesAStoppedChain() async throws {
        try await withTemporaryFolder { folder in
            let legacy = try LegacyStore(in: folder)
            let root = try legacy.entry(task: "Night", from: "2026-03-02T22:00", to: "2026-03-03T00:00", modified: 1000)
            let piece = try legacy.entry(root: root, task: "Renamed", from: "2026-03-03T00:00", to: "2026-03-03T01:30", modified: 5000)
            let store = try await legacy.open(clock: clock())
            #expect(TimeStore.schemaVersion == 4)
            let entry = try #require(try await store.entry(root))
            #expect(entry.task == "Night")
            #expect(try entry.end == date("2026-03-03T01:30"))
            #expect(entry.day.description == "2026-03-02")
            #expect(Int64(entry.modifiedAt.timeIntervalSince1970 * 1000) == 5001)
            #expect(try await store.entry(piece) == nil)
            #expect(try await store.entry(piece, includeDeleted: true)?.modifiedAt == entry.modifiedAt)
            let pending = try await store.pendingChanges()
            #expect(Set(pending.records.map(\.ref.name)) == [root.rawValue, piece.rawValue])
        }
    }

    @Test(
        "DATA-62 running chains over several nights merge; a chain broken by an edit, a gap left by a tombstone, and ordinary entries stay"
    )
    func keepsWhatIsNotContiguous() async throws {
        try await withTemporaryFolder { folder in
            let legacy = try LegacyStore(in: folder)
            let running = try legacy.entry(from: "2026-03-07T23:00", to: "2026-03-08T00:00")
            let second = try legacy.entry(root: running, from: "2026-03-08T00:00", to: "2026-03-09T00:00")
            let third = try legacy.entry(root: running, from: "2026-03-09T00:00", to: nil)
            // The user moved the second piece, so the chain is broken.
            let broken = try legacy.entry(from: "2026-03-05T22:00", to: "2026-03-06T00:00")
            let moved = try legacy.entry(root: broken, from: "2026-03-06T00:10", to: "2026-03-06T01:00")
            // The middle piece is deleted: the outer two stay apart.
            let gap = try legacy.entry(from: "2026-03-03T23:00", to: "2026-03-04T00:00")
            let deleted = try legacy.entry(root: gap, from: "2026-03-04T00:00", to: "2026-03-05T00:00", deleted: true)
            let outer = try legacy.entry(root: gap, from: "2026-03-05T00:00", to: "2026-03-05T01:00")
            // The first piece is deleted: the rest merge into the earliest live one.
            let gone = try legacy.entry(from: "2026-03-01T23:00", to: "2026-03-02T00:00", deleted: true)
            let head = try legacy.entry(root: gone, from: "2026-03-02T00:00", to: "2026-03-03T00:00")
            let tail = try legacy.entry(root: gone, from: "2026-03-03T00:00", to: "2026-03-03T02:00")
            let plain = try legacy.entry(from: "2026-03-01T08:00", to: "2026-03-01T09:00")
            let store = try await legacy.open(clock: clock())

            #expect(try await store.runningEntry()?.id == running)
            #expect(try await store.entry(running)?.end == nil)
            #expect(try await store.entry(second) == nil)
            #expect(try await store.entry(third) == nil)
            #expect(try await store.entry(broken)?.end == date("2026-03-06T00:00"))
            #expect(try await store.entry(moved)?.start == date("2026-03-06T00:10"))
            #expect(try await store.entry(gap)?.end == date("2026-03-04T00:00"))
            #expect(try await store.entry(outer) != nil)
            #expect(try await store.entry(deleted) == nil)
            #expect(try await store.entry(gone) == nil)
            #expect(try await store.entry(head)?.end == date("2026-03-03T02:00"))
            #expect(try await store.entry(tail) == nil)
            let pending = try await store.pendingChanges().records.map(\.ref.name)
            #expect(!pending.contains(plain.rawValue) && !pending.contains(broken.rawValue))
        }
    }

    @Test("DATA-62 a live_state row naming a merged piece names the whole entry, and its old fields decode")
    func repointsLiveState() async throws {
        try await withTemporaryFolder { folder in
            let legacy = try LegacyStore(in: folder)
            let root = try legacy.entry(task: "Night", from: "2026-03-09T23:00", to: "2026-03-10T00:00")
            let piece = try legacy.entry(root: root, task: "Night", from: "2026-03-10T00:00", to: nil)
            try legacy.liveState(
                #"{"entryID":"\#(piece.rawValue)","projectID":null,"task":"Night","chainStart":"2026-03-09T22:00:00Z"}"#,
                changedAt: 7000
            )
            let store = try await legacy.open(clock: clock())
            let live = try await store.liveState()
            #expect(live.running?.entryID == root)
            #expect(try live.running?.start == date("2026-03-09T23:00"))
            #expect(live.changedAt.map { Int64($0.timeIntervalSince1970 * 1000) } == 7001)
            let names = try await store.pendingChanges().records.map(\.ref)
            #expect(names.contains(SyncRecordRef(.liveState, "LiveState")))
        }
    }

    @Test("DATA-63 the merge is idempotent, drops the root column, and reopening changes nothing")
    func isIdempotent() async throws {
        try await withTemporaryFolder { folder in
            let legacy = try LegacyStore(in: folder)
            let root = try legacy.entry(from: "2026-03-02T22:00", to: "2026-03-03T00:00")
            try legacy.entry(root: root, from: "2026-03-03T00:00", to: "2026-03-03T01:30")
            try legacy.mergeChains()
            let rows = try legacy.rows()
            let outbox = try legacy.outboxCount()
            try legacy.mergeChains()
            #expect(try legacy.rows() == rows)
            #expect(try legacy.outboxCount() == outbox)

            let store = try await legacy.open(clock: clock())
            let pending = try await store.outboxCount()
            let again = try await legacy.open(clock: clock())
            #expect(try await again.outboxCount() == pending)
            let columns = try await DatabaseQueue(path: legacy.url.path).read { try $0.columns(in: "time_entry").map(\.name) }
            #expect(!columns.contains("split_root_id"))
        }
    }

    /// Two files holding the same chains: one stopped, one running.
    private func twins(in folder: TemporaryFolder, _ ids: [EntryID]) throws -> [LegacyStore] {
        try ["a.sqlite", "b.sqlite"].map { name in
            let legacy = try LegacyStore(in: folder, name: name)
            try legacy.entry(ids[0], task: "Night", from: "2026-03-02T22:00", to: "2026-03-03T00:00")
            try legacy.entry(ids[1], root: ids[0], task: "Other", from: "2026-03-03T00:00", to: "2026-03-03T01:30", modified: 2000)
            try legacy.entry(ids[2], from: "2026-03-09T23:00", to: "2026-03-10T00:00")
            try legacy.entry(ids[3], root: ids[2], from: "2026-03-10T00:00", to: nil)
            return legacy
        }
    }

    @Test("DATA-64 two devices migrate the same chains independently and agree, row for row; a third receives the result")
    func twoDevicesConverge() async throws {
        try await withTemporaryFolder { folder in
            let clock = try clock()
            let ids = [EntryID(), EntryID(), EntryID(), EntryID()]
            let legacy = try twins(in: folder, ids)
            let server = InMemorySyncServer(clock: clock)
            let storeA = try await legacy[0].open(clock: clock, device: DeviceID())
            let storeB = try await legacy[1].open(clock: clock, device: DeviceID())
            let syncA = StoreSynchronizer(store: storeA, transport: server.transport(for: "A"))
            let syncB = StoreSynchronizer(store: storeB, transport: server.transport(for: "B"))
            // Applied at different times, and the result must not differ.
            clock.advance(by: 3600)
            for _ in 0 ..< 2 {
                try await syncA.sync()
                try await syncB.sync()
            }
            let third = try await TestStore(clock: clock)
            try await StoreSynchronizer(store: third.store, transport: server.transport(for: "C")).sync()
            for store in [storeA, storeB, third.store] {
                #expect(try await store.outboxCount() == 0)
                #expect(try await store.entry(ids[0])?.end == date("2026-03-03T01:30"))
                #expect(try await store.entry(ids[0])?.task == "Night")
                #expect(try await store.entry(ids[1]) == nil)
                #expect(try await store.runningEntry()?.id == ids[2])
                #expect(try await store.entry(ids[3]) == nil)
            }
            let tombstoneA = try await storeA.entry(ids[1], includeDeleted: true)
            let tombstoneB = try await storeB.entry(ids[1], includeDeleted: true)
            #expect(tombstoneA == tombstoneB)
            #expect(try await storeA.entry(ids[0]) == storeB.entry(ids[0]))
        }
    }

    @Test("DATA-64 an edit made after one device migrated survives another device migrating later")
    func aLaterMigrationKeepsNewerEdits() async throws {
        try await withTemporaryFolder { folder in
            let clock = try clock()
            let first = try LegacyStore(in: folder, name: "a.sqlite")
            let second = try LegacyStore(in: folder, name: "b.sqlite")
            let root = EntryID()
            let piece = EntryID()
            for legacy in [first, second] {
                try legacy.entry(root, task: "Night", from: "2026-03-02T22:00", to: "2026-03-03T00:00")
                try legacy.entry(piece, root: root, task: "Night", from: "2026-03-03T00:00", to: "2026-03-03T01:30")
            }
            let server = InMemorySyncServer(clock: clock)
            let storeA = try await first.open(clock: clock, device: DeviceID())
            let syncA = StoreSynchronizer(store: storeA, transport: server.transport(for: "A"))
            try await syncA.sync()
            _ = try await storeA.update(root, EntryChange(task: "Edited after the migration"))
            try await syncA.sync()
            let storeB = try await second.open(clock: clock, device: DeviceID())
            let syncB = StoreSynchronizer(store: storeB, transport: server.transport(for: "B"))
            for _ in 0 ..< 2 {
                try await syncB.sync()
                try await syncA.sync()
            }
            #expect(try await storeA.entry(root)?.task == "Edited after the migration")
            #expect(try await storeB.entry(root)?.task == "Edited after the migration")
        }
    }

    @Test("DATA-65 a record from a device that lags behind decodes and its old fields are ignored, and pieces it still sends stay entries")
    func oldRecordsDecode() async throws {
        let test = try await TestStore()
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Whole",
            start: test.date("2024-03-13T22:00"),
            end: test.date("2024-03-14T01:00")
        ))
        let local = try #require(try await test.store.syncRecord(SyncRecordRef(.timeEntry, entry.id.rawValue)))
        // The same copy with the old field: nothing to apply, nothing to send.
        var old = local
        old["splitRootID"] = .string(EntryID().rawValue)
        let outbox = try await test.store.outboxCount()
        try await test.store.applyFetched([old], deletions: [])
        #expect(try await test.store.outboxCount() == outbox)
        #expect(try await test.store.entry(entry.id) == entry)
        // A new piece from such a device is an ordinary entry.
        let piece = EntryID()
        var record = local
        record.ref = SyncRecordRef(.timeEntry, piece.rawValue)
        record["splitRootID"] = .string(entry.id.rawValue)
        try await test.store.applyFetched([record], deletions: [])
        #expect(try await test.store.entry(piece)?.task == "Whole")
        let running = LiveState.running(json: #"{"entryID":"\#(piece.rawValue)","task":"","chainStart":"2024-03-14T10:00:00Z"}"#)
        #expect(try running?.start == TestTime.instant("2024-03-14T10:00:00Z"))
    }

    @Test("DATA-41 an export from before version 4 imports: its chains merge, and importing it over the migrated entry changes nothing")
    func oldExportImports() async throws {
        let test = try await TestStore(now: "2026-03-10T12:00")
        let root = EntryID()
        let piece = EntryID()
        let broken = EntryID()
        let late = EntryID()
        let document: [String: Any] = [
            "format": 1,
            "entries": [
                [
                    "id": root.rawValue,
                    "start": "2026-03-02T21:00:00Z",
                    "end": "2026-03-02T23:00:00Z",
                    "splitRootID": NSNull(),
                    "task": "Night",
                ],
                [
                    "id": piece.rawValue,
                    "start": "2026-03-02T23:00:00Z",
                    "end": "2026-03-03T00:30:00Z",
                    "splitRootID": root.rawValue,
                    "task": "Other",
                ],
                ["id": broken.rawValue, "start": "2026-03-03T21:00:00Z", "end": "2026-03-03T23:00:00Z"],
                ["id": late.rawValue, "start": "2026-03-03T23:30:00Z", "end": "2026-03-04T00:30:00Z", "splitRootID": broken.rawValue],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: document)
        let options = ImportOptions(defaultTimeZone: "Europe/Berlin")
        let report = try await test.store.importDocument(data, options: options)
        #expect(report[.entry].created == 3)
        #expect(try await test.store.entry(root)?.task == "Night")
        #expect(try await test.store.entry(root)?.end == test.date("2026-03-03T01:30"))
        #expect(try await test.store.entry(piece) == nil)
        #expect(try await test.store.entry(late) != nil)
        let again = try await test.store.importDocument(data, options: options)
        #expect(again.isNoOp)
    }
}
