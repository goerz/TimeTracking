// The LiveState snapshot, its batch, and its merge (spec_data_and_sync.md
// §4.1, §4.2; §9 items 32 and 33).

import Foundation
import Synchronization
import Testing
import TimeTrackingCore

/// Records every batch sent through it.
final class RecordingTransport: SyncTransport {
    let inner: any SyncTransport
    private let log = Mutex<[[SyncRecordRef]]>([])

    init(_ inner: any SyncTransport) {
        self.inner = inner
    }

    var batches: [[SyncRecordRef]] {
        log.withLock { $0 }
    }

    func send(saving records: [SyncRecord], deleting refs: [SyncRecordRef]) async throws -> [SyncSaveResult] {
        log.withLock { $0.append(records.map(\.ref) + refs) }
        return try await inner.send(saving: records, deleting: refs)
    }

    func fetchChanges(since token: Data?) async throws -> SyncFetchResult {
        try await inner.fetchChanges(since: token)
    }

    func createZone() async throws {
        try await inner.createZone()
    }
}

struct LiveStateTests {
    static let liveRef = SyncRecordRef(.liveState, "LiveState")

    @Test("DATA-32 a start writes the snapshot and queues LiveState in its transaction and batch; a stop clears it; a split keeps it")
    func snapshotOnWrite() async throws {
        let test = try await TestStore(now: "2024-03-14T23:00")
        let store = test.store
        let made = try await test.structure(projects: ["Paper"])
        try await store.updateArea(made.area.id, AreaChange(color: "#2E8BC0"))
        let start = try test.date("2024-03-14T22:30")
        let before = try await store.outboxCount()
        let entry = try await store.start(projectID: made.projects[0].id, task: "Draft", at: start)
        #expect(try await store.outboxCount() == before + 2)
        let pending = try await store.pendingChanges()
        #expect(pending.records.map(\.ref).contains(Self.liveRef))
        #expect(pending.records.map(\.ref).contains(SyncRecordRef(.timeEntry, entry.id.rawValue)))

        let running = try #require(try await store.liveState().running)
        #expect(running.entryID == entry.id)
        #expect(running.projectID == made.projects[0].id)
        #expect(running.task == "Draft")
        #expect(running.projectName == "Paper")
        #expect(running.clientName == made.client.name)
        #expect(running.areaColor == "#2E8BC0")
        #expect(running.chainStart == start)
        let json = try #require(LiveState.runningJSON(running))
        #expect(json.contains("\"chainStart\":\"2024-03-14T21:30:00Z\""))
        #expect(try await store.liveState().changedAt == test.clock.now)

        let server = InMemorySyncServer(clock: test.clock)
        let transport = RecordingTransport(server.transport(for: "A"))
        try await StoreSynchronizer(store: store, transport: transport).sync()
        let batch = try #require(transport.batches.first { $0.contains(Self.liveRef) })
        #expect(batch.contains(SyncRecordRef(.timeEntry, entry.id.rawValue)))

        // The midnight split names the continuation with the same chain start.
        try test.clock.set(test.date("2024-03-15T00:10"))
        try await store.checkInvariants()
        let continued = try #require(try await store.liveState().running)
        #expect(continued.entryID != entry.id)
        #expect(try await continued.entryID == (store.runningEntry())?.id)
        #expect(continued.chainStart == start)

        _ = try await store.stop(at: test.clock.now)
        #expect(try await store.liveState().running == nil)
        let synchronizer = StoreSynchronizer(store: store, transport: transport)
        try await synchronizer.sync()
        let record = try #require(await server.record(Self.liveRef))
        #expect(record["running"] == nil)
        #expect(record["changedAt"] != nil)
    }

    @Test("DATA-33 a receiver queues no LiveState; a rename there queues the new name; conflicts merge per §4.1")
    func receiverAndMerge() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        let made = try await peerA.test.structure(projects: ["Paper"])
        _ = try await peerA.store.start(projectID: made.projects[0].id, task: "Draft", at: net.date("2024-03-14T09:00"))
        try await net.converge()
        #expect(try await peerB.store.outboxCount() == 0)
        #expect(try await peerB.store.liveState() == (peerA.store.liveState()))
        let changedAt = try await peerB.store.liveState().changedAt

        net.clock.advance(by: 30)
        try await peerB.store.updateProject(made.projects[0].id, ProjectChange(name: "Paper II"))
        let pending = try await peerB.store.pendingChanges()
        let record = try #require(pending.records.first { $0.ref == Self.liveRef })
        #expect(LiveState.running(json: record["running"]?.string)?.projectName == "Paper II")
        #expect(try await peerB.store.liveState().changedAt != changedAt)
        try await net.converge()
        #expect(try await peerA.store.liveState().running?.projectName == "Paper II")

        // Partitioned: A changes the running part and two activity entries,
        // B later changes one of them and adds another.
        let (macA, macB, macC) = (DeviceID(), DeviceID(), DeviceID())
        await net.partition(true)
        net.clock.advance(by: 30)
        let second = try await peerA.store.start(projectID: nil, task: "Review", at: net.clock.now)
        try await peerA.store.setLiveActivity(Self.activity("from A", at: net.clock.now), for: macA)
        try await peerA.store.setLiveActivity(Self.activity("only A", at: net.clock.now), for: macC)
        net.clock.advance(by: 30)
        try await peerB.store.setLiveActivity(Self.activity("later B", at: net.clock.now), for: macA)
        try await peerB.store.setLiveActivity(Self.activity("only B", at: net.clock.now), for: macB)
        await net.partition(false)
        try await net.converge()
        try await net.converge()
        #expect(await net.server.conflictCount >= 1)
        for peer in net.peers {
            let state = try await peer.store.liveState()
            #expect(state.running?.entryID == second.id)
            #expect(state.activity[macA.rawValue]?.device == "later B")
            #expect(state.activity[macB.rawValue]?.device == "only B")
            #expect(state.activity[macC.rawValue]?.device == "only A")
            #expect(try await peer.store.outboxCount() == 0)
        }
    }

    @Test("DATA-33 the merge keeps the later running part and the later activity per Mac")
    func mergeRule() {
        let early = Date(timeIntervalSince1970: 1_710_000_000)
        let late = early + 60
        let running = LiveState.Running(
            entryID: EntryID(),
            projectID: nil,
            task: "x",
            projectName: nil,
            clientName: nil,
            areaColor: nil,
            chainStart: early
        )
        let local = LiveState(running: nil, changedAt: late, activity: ["a": Self.activity("local a", at: late)])
        let remote = LiveState(running: running, changedAt: early, activity: [
            "a": Self.activity("remote a", at: early),
            "b": Self.activity("remote b", at: early),
        ])
        let merged = local.merged(with: remote)
        #expect(merged.running == nil)
        #expect(merged.changedAt == late)
        #expect(merged.activity["a"]?.device == "local a")
        #expect(merged.activity["b"]?.device == "remote b")
        #expect(remote.merged(with: local) == merged)
        #expect(LiveState.activity(json: LiveState.activityJSON(merged.activity)) == merged.activity)
        #expect(LiveState.running(json: LiveState.runningJSON(running)) == running)
    }

    static func activity(_ device: String, at time: Date) -> LiveState.MacActivity {
        LiveState.MacActivity(
            device: device,
            primary: TrackerPrimaryItem(context: "tmux:paper", subject: "draft", detail: "nvim"),
            groupKey: "tmux:paper",
            presence: "active",
            since: time,
            agentRunning: true,
            lastTick: time,
            health: [],
            updatedAt: time
        )
    }
}
