// SyncCoordinator against a simulated engine over InMemoryTransport
// (spec_data_and_sync.md §3.1, §4.3).

import CryptoKit
import Foundation
import Synchronization
import Testing
import TimeTrackingCore

/// One device: a store and its coordinator with a simulated engine.
private struct SyncDevice {
    let test: TestStore
    let coordinator: SyncCoordinator
    let factory: SimulatedEngineFactory

    init(_ name: String, server: InMemorySyncServer, clock: ManualClock) async throws {
        self.test = try await TestStore(clock: clock)
        self.factory = SimulatedEngineFactory(server: server, device: name)
        self.coordinator = SyncCoordinator(store: test.store, factory: factory)
        await coordinator.start(observingStore: false)
    }

    var store: TimeStore {
        test.store
    }

    var engine: SimulatedSyncEngine? {
        factory.engine
    }

    /// What the store's change stream would trigger, then a fetch.
    func cycle() async {
        await coordinator.storeChanged(.entries([]))
        await coordinator.sendNow()
        await coordinator.fetchNow()
    }
}

/// Two devices on one server.
private struct SyncPair {
    let server: InMemorySyncServer
    let clock: ManualClock
    let first: SyncDevice
    let second: SyncDevice
}

/// Collects events from a handler.
private final class Events<Event: Sendable>: Sendable {
    private let log = Mutex<[Event]>([])

    var all: [Event] {
        log.withLock { $0 }
    }

    func append(_ event: Event) {
        log.withLock { $0.append(event) }
    }
}

struct SyncCoordinatorTests {
    private static func pair() async throws -> SyncPair {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let clock = try ManualClock(TestStore.date("2024-03-14T10:00", zone))
        let server = InMemorySyncServer(clock: clock)
        return try await SyncPair(
            server: server,
            clock: clock,
            first: SyncDevice("A", server: server, clock: clock),
            second: SyncDevice("B", server: server, clock: clock)
        )
    }

    @Test("DATA-32 the coordinator sends a start at once, LiveState and the entry in one atomic batch")
    func startIsSentAtOnce() async throws {
        let net = try await Self.pair()
        let (server, deviceA, deviceB) = (net.server, net.first, net.second)
        let events = Events<LiveStateSyncEvent>()
        await deviceA.coordinator.onLiveState { events.append($0) }
        let entry = try await deviceA.store.start(projectID: nil, task: "Paper", at: deviceA.test.date("2024-03-14T09:00"))
        await deviceA.coordinator.storeChanged(.entries([entry.id]))
        await deviceA.coordinator.storeChanged(.runningEntry(entry))
        #expect(await server.record(SyncRecordRef(.timeEntry, entry.id.rawValue)) != nil)
        #expect(await server.record(SyncRecordRef(.liveState, "LiveState")) != nil)
        let batch = try #require(deviceA.engine?.batches.first { batch in batch.records.contains { $0.ref.type == .liveState } })
        #expect(batch.atomic)
        #expect(batch.records.map(\.ref).contains(SyncRecordRef(.timeEntry, entry.id.rawValue)))
        #expect(try await deviceA.store.outboxCount() == 0)
        #expect(deviceA.engine?.pending.isEmpty == true)
        #expect(events.all.contains { event in
            if case .saved = event {
                true
            } else {
                false
            }
        })

        let fetched = Events<LiveStateSyncEvent>()
        await deviceB.coordinator.onLiveState { fetched.append($0) }
        await deviceB.coordinator.fetchNow()
        #expect(try await deviceB.store.runningEntry()?.id == entry.id)
        #expect(try await fetched.all == [.fetched(deviceB.store.liveState(), runningChanged: true)])
        #expect(try await deviceB.store.outboxCount() == 0)
    }

    @Test("DATA-55 an edit made while its record is being sent stays queued and goes out with the next send")
    func editDuringSend() async throws {
        let net = try await Self.pair()
        let device = net.first
        let engine = try #require(device.engine)
        let entry = try await device.store.create(EntryDraft(
            projectID: nil,
            task: "Draft",
            start: device.test.date("2024-03-14T08:00"),
            end: device.test.date("2024-03-14T09:00")
        ))
        let ref = SyncRecordRef(.timeEntry, entry.id.rawValue)
        _ = await device.coordinator.drain()
        // The engine takes the batch; the user edits before the server answers.
        let batch = try #require(await device.coordinator.nextBatch(engine.pending))
        #expect(batch.records.map(\.ref).contains(ref))
        _ = try await device.store.update(entry.id, EntryChange(task: "Draft, edited"))
        engine.removePending(engine.pending)
        await device.coordinator.didSend(SyncSendOutcome(saved: batch.records))
        #expect(engine.pending.contains(.save(ref)))
        #expect(try await device.store.outboxCount() >= 1)
        await device.coordinator.sendNow()
        #expect(await net.server.record(ref)?["task"] == .string("Draft, edited"))
        #expect(try await device.store.outboxCount() == 0)
    }

    @Test("DATA-29 through the coordinator a conflict merges once and a missing zone re-sends every record")
    func conflictsAndZone() async throws {
        let net = try await Self.pair()
        let (server, clock, deviceA, deviceB) = (net.server, net.clock, net.first, net.second)
        let entry = try await deviceA.store.create(EntryDraft(
            projectID: nil,
            task: "x",
            start: deviceA.test.date("2024-03-14T08:00"),
            end: deviceA.test.date("2024-03-14T08:30")
        ))
        await deviceA.cycle()
        await deviceB.cycle()
        _ = try await deviceA.store.update(entry.id, EntryChange(task: "from A"))
        clock.advance(by: 1)
        _ = try await deviceB.store.update(entry.id, EntryChange(task: "from B"))
        await deviceA.cycle()
        await deviceB.cycle()
        await deviceA.cycle()
        #expect(await server.conflictCount == 1)
        for device in [deviceA, deviceB] {
            #expect(try await device.store.entry(entry.id)?.task == "from B")
            #expect(try await device.store.outboxCount() == 0)
        }

        await server.deleteZone()
        _ = try await deviceA.store.update(entry.id, EntryChange(task: "after reset"))
        await deviceA.cycle()
        await deviceA.coordinator.sendNow()
        #expect(await server.record(SyncRecordRef(.timeEntry, entry.id.rawValue))?["task"] == .string("after reset"))
        #expect(await server.allRecords.count == 1)
        #expect(try await deviceA.store.outboxCount() == 0)
    }

    @Test("DATA-31 outbox rows written by another instance are sent by the coordinator's instance")
    func otherInstanceRows() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store.sqlite")
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let clock = try ManualClock(TestStore.date("2024-03-14T10:00", zone))
        let device = DeviceID()
        let app = try await TimeStore.open(.init(location: .file(url), clock: clock, deviceID: device, timeZone: { zone }))
        let tool = try await TimeStore.open(.init(location: .file(url), clock: clock, deviceID: device, timeZone: { zone }))
        let server = InMemorySyncServer(clock: clock)
        let coordinator = SyncCoordinator(store: app, factory: SimulatedEngineFactory(server: server, device: "Mac"))
        await coordinator.start(observingStore: false)
        let entry = try await tool.start(projectID: nil, task: "From the tool", at: clock.now)
        // The Darwin notification arrives as these events.
        await coordinator.storeChanged(.entries([]))
        await coordinator.storeChanged(.runningEntry(nil))
        #expect(await server.record(SyncRecordRef(.timeEntry, entry.id.rawValue)) != nil)
        #expect(try await tool.outboxCount() == 0)
    }

    @Test("an account switch empties the store after confirmation; declined, sync stops and data stays")
    func accountChanges() async throws {
        let net = try await Self.pair()
        let (deviceA, deviceB) = (net.first, net.second)
        _ = try await deviceA.store.start(projectID: nil, task: "Paper", at: deviceA.test.date("2024-03-14T09:00"))
        await deviceA.coordinator.accountChanged(.signOut)
        #expect(await deviceA.coordinator.status == .noAccount)
        #expect(try await deviceA.store.runningEntry() != nil)

        await deviceA.coordinator.onAccountSwitch { false }
        await deviceA.coordinator.accountChanged(.switchAccounts)
        #expect(await deviceA.coordinator.isRunning == false)
        #expect(try await deviceA.store.runningEntry() != nil)

        _ = try await deviceB.store.start(projectID: nil, task: "Other", at: deviceB.test.date("2024-03-14T09:00"))
        await deviceB.coordinator.onAccountSwitch { true }
        await deviceB.coordinator.accountChanged(.switchAccounts)
        #expect(try await deviceB.store.runningEntry() == nil)
        #expect(try await deviceB.store.liveState() == LiveState())
        #expect(try await deviceB.store.outboxCount() == 0)
        #expect(await deviceB.coordinator.isRunning)
    }

    @Test("without CloudKit the coordinator reports an error and the store keeps working locally")
    func unavailableContainer() async throws {
        let test = try await TestStore()
        let statuses = test.store.changes
        let coordinator = SyncCoordinator(store: test.store, factory: UnavailableEngineFactory())
        await coordinator.start()
        #expect(await coordinator.isRunning == false)
        guard case .error = await coordinator.status else {
            Issue.record("expected an error status")
            return
        }
        for await change in statuses {
            if case .sync(.error) = change {
                break
            }
        }
        let entry = try await test.store.start(projectID: nil, task: "Offline", at: test.date("2024-03-14T09:00"))
        #expect(try await test.store.runningEntry()?.id == entry.id)
        #expect(await coordinator.drain() == 0)
        await coordinator.sendNow()
        await coordinator.fetchNow()
        #expect(try await test.store.outboxCount() == 2)

        // The real factory refuses before touching CloudKit in an unentitled process.
        let container = "iCloud.com.example.timetracking"
        #expect(CloudKitAvailability.check(containerIdentifier: container) == false)
        let real = SyncCoordinator(store: test.store, factory: CloudKitSyncEngineFactory(containerIdentifier: container))
        await real.start()
        #expect(await real.isRunning == false)
    }

    @Test("DATA-35 the coordinator's LiveState events drive the widget pushes")
    func pushesFromCoordinator() async throws {
        let net = try await Self.pair()
        let (clock, deviceA) = (net.clock, net.first)
        let http = RecordingHTTP()
        let client = APNsClient(
            credentials: StaticAPNsCredentials(APNsCredentials(
                keyID: "ABC123DEFG",
                teamID: "T",
                privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
            )),
            topic: "X.push-type.widgets",
            clock: clock,
            http: http
        )
        let sender = WidgetPushSender(store: deviceA.store, client: client, clock: clock)
        await deviceA.coordinator.onLiveState { await sender.handle($0) }
        let phone = SyncRecord(ref: SyncRecordRef(.device, DeviceID().rawValue), fields: [
            "name": .string("iPhone"), "platform": .string("iphone"), "widgetPushToken": .string("aa11"),
            "lastSeenAt": .date(clock.now), "createdAt": .date(clock.now), "modifiedAt": .date(clock.now),
        ])
        try await deviceA.store.applyFetched([phone], deletions: [])
        let entry = try await deviceA.store.start(projectID: nil, task: "Paper", at: clock.now)
        await deviceA.coordinator.storeChanged(.runningEntry(entry))
        #expect(http.requests.compactMap { $0.url?.lastPathComponent } == ["aa11"])
    }
}
