// The start of day's old key `day.midnightHour` becomes `day.startHour`
// on every device (data_and_sync.md §8; §9 item 66).

import Foundation
import GRDB
import Testing
@testable import TimeTrackingCore

struct SettingRenameTests {
    private static let legacyKey = SyncedSettingKey<Int>("day.midnightHour", default: -1)
    private static let legacyRef = SyncRecordRef(.setting, "day.midnightHour")
    private static let newRef = SyncRecordRef(.setting, "day.startHour")

    /// The record a device with an older app sends for the start of day.
    private static func legacyRecord(_ hour: Int, at modified: Date) -> SyncRecord {
        SyncRecord(ref: legacyRef, fields: ["value": .string(String(hour)), "modifiedAt": .date(modified)])
    }

    @Test("DATA-66 a store holding day.midnightHour at 04:00 opens with day.startHour at 04:00 and the old record a tombstone")
    func renamesOnOpen() async throws {
        try await withTemporaryFolder { folder in
            let url = folder.url.appending(path: "store.sqlite")
            let queue = try DatabaseQueue(path: url.path)
            try Schema.migrator.migrate(queue)
            try await queue.write { database in
                try database.execute(
                    sql: "INSERT INTO setting (key, value, modified_at) VALUES ('day.midnightHour', '4', 1000)"
                )
            }
            try queue.close()
            let clock = ManualClock.fixture(in: TestTime.berlin)
            let store = try await TimeStore.open(
                .init(location: .file(url), clock: clock, deviceID: DeviceID(), timeZone: { TestTime.berlin })
            )
            #expect(try await store.value(.startOfDayHour) == 4)
            #expect(store.displayCalendar(timeZone: TestTime.berlin).startOfDayHour == 4)
            #expect(try await store.value(Self.legacyKey) == -1)
            let new = try #require(try await store.syncRecord(Self.newRef))
            #expect(new.modifiedMillis == 1000)
            let old = try #require(try await store.syncRecord(Self.legacyRef))
            #expect(old.isDeleted)
            #expect(old.modifiedMillis == 1001)
            let pending = try await store.pendingChanges()
            #expect(Set(pending.records.map(\.ref)) == [Self.newRef, Self.legacyRef])
            // A second pass changes nothing.
            let outbox = try await store.outboxCount()
            try await store.checkInvariants()
            #expect(try await store.outboxCount() == outbox)
        }
    }

    @Test(
        "DATA-66 a day.midnightHour record from sync ends as day.startHour on every device; a device holding both keeps day.startHour"
    )
    func renamesOnSync() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        try await peerA.store.applyFetched([Self.legacyRecord(4, at: net.clock.now)], deletions: [])
        #expect(try await peerA.store.value(.startOfDayHour) == 4)
        #expect(try await peerA.store.value(Self.legacyKey) == -1)
        try await net.converge()
        for peer in net.peers {
            #expect(try await peer.store.value(.startOfDayHour) == 4)
            #expect(try await peer.store.value(Self.legacyKey) == -1)
            #expect(peer.store.displayCalendar().startOfDayHour == 4)
        }
        #expect(await net.server.record(Self.newRef)?.isDeleted == false)
        #expect(await net.server.record(Self.legacyRef)?.isDeleted == true)

        // The start of day set on B, then an older app writes the old key again.
        net.clock.advance(by: 60)
        try await peerB.store.set(.startOfDayHour, 6)
        try await net.converge()
        net.clock.advance(by: 60)
        try await peerA.store.applyFetched([Self.legacyRecord(9, at: net.clock.now)], deletions: [])
        try await net.converge()
        for peer in net.peers {
            #expect(try await peer.store.value(.startOfDayHour) == 6)
            #expect(try await peer.store.value(Self.legacyKey) == -1)
        }
        #expect(await net.server.record(Self.legacyRef)?.isDeleted == true)
    }
}
