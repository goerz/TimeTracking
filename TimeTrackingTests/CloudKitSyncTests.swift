// CloudKitTransport and the LiveState fetch against the Debug container, in
// a zone each test creates and deletes (spec_data_and_sync.md §3.3;
// spec_architecture.md §3.1). Runs only with TIMETRACKING_TEST_SYNC=1
// (`make test-sync`): it needs the signed Debug build and an iCloud account.

import Foundation
import Testing
import TimeTrackingCore

extension Tag {
    @Tag static var sync: Self
}

/// A test zone of the Debug container, deleted at the end.
private struct TestZone {
    let transport: CloudKitTransport

    init() async throws {
        let identity = try #require(AppIdentity.main)
        try #require(CloudKitAvailability.check(containerIdentifier: identity.cloudKitContainer), "not entitled to iCloud")
        self.transport = CloudKitTransport(containerIdentifier: identity.cloudKitContainer, zoneName: "Test-\(UUID().uuidString)")
        try await transport.createZone()
    }

    func delete() async {
        try? await transport.deleteZone()
    }
}

@Suite(.tags(.sync), .enabled(if: ProcessInfo.processInfo.environment["TIMETRACKING_TEST_SYNC"] == "1"), .serialized)
struct CloudKitSyncTests {
    @Test("CloudKitTransport saves, fetches, rejects a stale copy, and deletes, field for field")
    func roundTrip() async throws {
        let zone = try await TestZone()
        defer { Task { await zone.delete() } }
        let clock = ManualClock.fixture()
        let store = try await TimeStore.inMemory(clock: clock)
        let entry = try await store.start(projectID: nil, task: "Paper", at: clock.now - 600)
        let pending = try await store.pendingChanges()
        let results = try await zone.transport.send(saving: pending.records, deleting: [])
        let saved = results.compactMap { result -> SyncRecord? in
            if case let .saved(record) = result {
                return record
            }
            return nil
        }
        #expect(saved.count == pending.records.count)
        #expect(saved.allSatisfy { $0.systemFields != nil })

        let fetched = try await zone.transport.fetchChanges(since: nil)
        let remote = try #require(fetched.records.first { $0.ref == SyncRecordRef(.timeEntry, entry.id.rawValue) })
        let local = try #require(pending.records.first { $0.ref == remote.ref })
        #expect(remote.canonicalFields == local.canonicalFields)
        let again = try await zone.transport.fetchChanges(since: fetched.token)
        #expect(again.records.isEmpty)

        // A copy without the server's system fields is rejected with the server's record.
        var stale = local
        stale["task"] = .string("stale")
        let conflict = try await zone.transport.send(saving: [stale], deleting: [])
        guard case let .conflict(server) = conflict.first else {
            Issue.record("expected a conflict, got \(conflict)")
            return
        }
        #expect(server["task"] == .string("Paper"))

        let deleted = try await zone.transport.send(saving: [], deleting: [remote.ref])
        #expect(deleted == [.deleted(remote.ref)])
        let afterDelete = try await zone.transport.fetchChanges(since: fetched.token)
        #expect(afterDelete.deletions.contains(remote.ref))
    }

    @Test("Two stores converge through CloudKit, and LiveStateReader fetches the running entry")
    func twoStoresAndLiveState() async throws {
        let zone = try await TestZone()
        defer { Task { await zone.delete() } }
        let clock = ManualClock.fixture()
        let first = try await TimeStore.inMemory(clock: clock)
        let second = try await TimeStore.inMemory(clock: clock)
        let entry = try await first.start(projectID: nil, task: "Paper", at: clock.now - 60)
        try await StoreSynchronizer(store: first, transport: zone.transport).sync()
        try await StoreSynchronizer(store: second, transport: zone.transport).sync()
        #expect(try await second.runningEntry()?.id == entry.id)
        #expect(try await second.outboxCount() == 0)

        let live = try await LiveStateReader(transport: zone.transport).fetch(timeout: 20)
        #expect(live.running?.entryID == entry.id)
        #expect(live.running?.task == "Paper")
    }
}
