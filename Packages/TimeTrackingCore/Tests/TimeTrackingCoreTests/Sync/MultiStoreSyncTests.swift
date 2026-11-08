// Several stores against InMemoryTransport (data_and_sync.md §3; §9 items 23 to 31).

import Foundation
import Testing
import TimeTrackingCore

/// One simulated device: a store and its sync loop.
struct Peer {
    let test: TestStore
    let sync: StoreSynchronizer
    let name: String

    init(_ name: String, server: InMemorySyncServer, clock: ManualClock) async throws {
        self.name = name
        self.test = try await TestStore(clock: clock)
        self.sync = StoreSynchronizer(store: test.store, transport: server.transport(for: name))
    }

    var store: TimeStore {
        test.store
    }
}

struct Network {
    let clock: ManualClock
    let server: InMemorySyncServer
    let peers: [Peer]

    init(_ names: [String] = ["A", "B"], now: String = "2024-03-14T10:00") async throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        self.clock = try ManualClock(TestStore.date(now, zone))
        self.server = InMemorySyncServer(clock: clock)
        var peers: [Peer] = []
        for name in names {
            try await peers.append(Peer(name, server: server, clock: clock))
        }
        self.peers = peers
    }

    /// Every device syncs, twice round, so changes reach everyone.
    func converge() async throws {
        for _ in 0 ..< 2 {
            for peer in peers {
                try await peer.sync.sync()
            }
        }
    }

    func partition(_ isPartitioned: Bool) async {
        for peer in peers {
            await server.setPartitioned(peer.name, isPartitioned)
        }
    }

    func date(_ text: String) throws -> Date {
        try peers[0].test.date(text)
    }
}

struct MultiStoreSyncTests {
    @Test("DATA-25 a start on A appears on B after one cycle with identical id, start, end, and day")
    func startPropagates() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        let entry = try await peerA.store.start(projectID: nil, task: "Paper", at: net.date("2024-03-14T09:00"))
        try await peerA.sync.sync()
        try await peerB.sync.sync()
        let received = try #require(try await peerB.store.runningEntry())
        #expect(received.id == entry.id)
        #expect(received.start == entry.start)
        #expect(received.end == entry.end)
        #expect(received.day == entry.day)
        #expect(try await peerB.store.outboxCount() == 0)
    }

    @Test("DATA-26 partitioned starts at 09:00 on A and 09:10 on B converge to A ending at 09:10 and B running")
    func partitionedStarts() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        await net.partition(true)
        let first = try await peerA.store.start(projectID: nil, task: "A", at: net.date("2024-03-14T09:00"))
        let second = try await peerB.store.start(projectID: nil, task: "B", at: net.date("2024-03-14T09:10"))
        try await net.converge()
        #expect(await peerA.sync.status == .waitingForNetwork)
        await net.partition(false)
        try await net.converge()
        for peer in net.peers {
            #expect(try await peer.store.entry(first.id)?.end == (net.date("2024-03-14T09:10")))
            #expect(try await peer.store.runningEntry()?.id == second.id)
        }
    }

    @Test("DATA-27 the later of a rename and an archive wins on both; an edit after a deletion resurrects the entry")
    func lastWriterWins() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        let project = try await peerA.test.structure(projects: ["Paper"]).projects[0]
        let entry = try await peerA.store.create(EntryDraft(
            projectID: project.id,
            task: "x",
            start: net.date("2024-03-14T08:00"),
            end: net.date("2024-03-14T08:30")
        ))
        try await net.converge()
        await net.partition(true)
        try await peerA.store.updateProject(project.id, ProjectChange(name: "Renamed"))
        try await peerA.store.delete([entry.id])
        net.clock.advance(by: 60)
        try await peerB.store.archive(project.id)
        _ = try await peerB.store.update(entry.id, EntryChange(task: "edited"))
        await net.partition(false)
        try await net.converge()
        for peer in net.peers {
            let merged = try #require(try await peer.store.project(project.id))
            #expect(merged.isArchived)
            #expect(merged.name == "Paper")
            #expect(try await peer.store.entry(entry.id)?.task == "edited")
        }
    }

    @Test("DATA-28 an entry whose project arrives later is kept and reported until the project arrives")
    func danglingProject() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        let made = try await peerA.test.structure(projects: ["Paper"])
        let entry = try await peerA.store.create(EntryDraft(
            projectID: made.projects[0].id,
            task: "x",
            start: net.date("2024-03-14T08:00"),
            end: net.date("2024-03-14T08:30")
        ))
        try await peerA.sync.sync()
        let entryRecord = try #require(await net.server.record(SyncRecordRef(.timeEntry, entry.id.rawValue)))
        try await peerB.store.applyFetched([entryRecord], deletions: [])
        #expect(try await peerB.store.entry(entry.id) != nil)
        #expect(try await peerB.store.consistencyIssues() == [.unknownProject(entry.id, projectID: made.projects[0].id)])
        try await peerB.sync.sync()
        #expect(try await peerB.store.consistencyIssues().isEmpty)
    }

    @Test("DATA-29 a conflict resolves without a second rejection; zoneNotFound re-sends everything; old tombstones vanish")
    func conflictsAndZones() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        let entry = try await peerA.store.create(EntryDraft(
            projectID: nil,
            task: "x",
            start: net.date("2024-03-14T08:00"),
            end: net.date("2024-03-14T08:30")
        ))
        try await net.converge()
        _ = try await peerA.store.update(entry.id, EntryChange(task: "from A"))
        net.clock.advance(by: 1)
        _ = try await peerB.store.update(entry.id, EntryChange(task: "from B"))
        try await peerA.sync.sync()
        try await peerB.sync.sync()
        try await net.converge()
        #expect(await net.server.conflictCount == 1)
        for peer in net.peers {
            #expect(try await peer.store.entry(entry.id)?.task == "from B")
        }

        let doomed = try await peerA.store.create(EntryDraft(
            projectID: nil,
            task: "y",
            start: net.date("2024-03-14T09:00"),
            end: net.date("2024-03-14T09:10")
        ))
        try await peerA.store.delete([doomed.id])
        try await net.converge()
        await net.server.deleteZone()
        try await peerA.sync.sync()
        let names = await Set(net.server.allRecords.map(\.ref.name))
        #expect(names.isSuperset(of: [entry.id.rawValue, doomed.id.rawValue]))
        #expect(await net.server.record(SyncRecordRef(.timeEntry, doomed.id.rawValue))?.isDeleted == true)

        net.clock.advance(by: 181 * 86_400)
        try await peerA.store.purgeExpiredTombstones()
        try await net.converge()
        for peer in net.peers {
            let all = try await peer.store.entries(
                in: DateInterval(start: net.date("2024-03-14T00:00"), duration: 86_400),
                includeDeleted: true
            )
            #expect(all.map(\.id) == [entry.id])
        }
    }

    @Test("DATA-30 settings converge per key to the later value; activity.appColors to the union")
    func settingsMerge() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        await net.partition(true)
        try await peerA.store.set(.pomodoroFocusMinutes, 30)
        try await peerA.store.set(.activityAppColors, ["Mail": 1, "WezTerm": 2])
        net.clock.advance(by: 5)
        try await peerB.store.set(.pomodoroFocusMinutes, 45)
        try await peerB.store.set(.activityAppColors, ["Mail": 0, "Safari": 3])
        await net.partition(false)
        try await net.converge()
        for peer in net.peers {
            #expect(try await peer.store.value(.pomodoroFocusMinutes) == 45)
            #expect(try await peer.store.value(.activityAppColors) == ["Mail": 0, "WezTerm": 2, "Safari": 3])
        }
        #expect(SettingMerge.hueIndex(forNewAppIn: ["a": 0, "b": 1, "c": 0], hueCount: 3) == 2)
    }

    @Test("DATA-31 outbox rows of a second instance without an engine are sent by the engine's instance")
    func secondInstance() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let url = folder.url.appending(path: "store.sqlite")
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let clock = try ManualClock(TestStore.date("2024-03-14T10:00", zone))
        let device = DeviceID()
        let app = try await TimeStore.open(.init(location: .file(url), clock: clock, deviceID: device, timeZone: { zone }))
        let tool = try await TimeStore.open(.init(location: .file(url), clock: clock, deviceID: device, timeZone: { zone }))
        let server = InMemorySyncServer(clock: clock)
        let engine = StoreSynchronizer(store: app, transport: server.transport(for: "Mac"))
        let entry = try await tool.start(projectID: nil, task: "From the tool", at: clock.now)
        #expect(try await app.outboxCount() == 2) // the entry and LiveState
        try await engine.sync()
        #expect(await server.record(SyncRecordRef(.timeEntry, entry.id.rawValue)) != nil)
        #expect(try await tool.outboxCount() == 0)
    }

    @Test("DATA-23 the cross-midnight example converges on both devices and a second pass changes nothing")
    func crossMidnightExample() async throws {
        let net = try await Network(now: "2026-10-28T23:45")
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        await net.partition(true)
        let first = try await peerA.store.start(projectID: nil, task: "X", at: net.date("2026-10-28T23:00"))
        let second = try await peerB.store.start(projectID: nil, task: "Y", at: net.date("2026-10-28T23:30"))
        try net.clock.set(net.date("2026-10-29T00:30"))
        await net.partition(false)
        try await net.converge()
        for peer in net.peers {
            #expect(try await peer.store.entry(first.id)?.end == (net.date("2026-10-28T23:30")))
            #expect(try await peer.store.runningEntry()?.id == second.id)
            let outbox = try await peer.store.outboxCount()
            try await peer.store.checkInvariants()
            #expect(try await peer.store.outboxCount() == outbox)
        }
    }

    @Test("DATA-19 a device asleep from Monday 22:00 to Wednesday 10:00 and one awake throughout hold one running entry after sync")
    func runningEntryConverges() async throws {
        let net = try await Network(now: "2026-10-26T22:00")
        let (sleeper, awake) = (net.peers[0], net.peers[1])
        let entry = try await sleeper.store.start(projectID: nil, task: "Long", at: net.date("2026-10-26T22:00"))
        try await net.converge()
        #expect(try await awake.store.runningEntry() == entry)
        try net.clock.set(net.date("2026-10-28T10:00"))
        try await net.converge()
        let interval = try DateInterval(start: net.date("2026-10-26T00:00"), end: net.date("2026-10-29T00:00"))
        for peer in net.peers {
            #expect(try await peer.store.entries(in: interval) == [entry])
            #expect(try await peer.store.outboxCount() == 0)
        }
    }

    @Test("DATA-24 .adjusted with stoppedByLaterStart reaches only the device that created the entry")
    func adjustedEvents() async throws {
        let net = try await Network(["A", "B", "C"], now: "2026-10-28T23:50")
        let (peerA, peerB, peerC) = (net.peers[0], net.peers[1], net.peers[2])
        let eventsA = peerA.store.changes
        let eventsC = peerC.store.changes
        await net.partition(true)
        let own = try await peerA.store.start(projectID: nil, task: "A", at: net.date("2026-10-28T23:40"))
        try net.clock.set(net.date("2026-10-29T00:05"))
        let later = try await peerB.store.start(projectID: nil, task: "B", at: net.date("2026-10-29T00:04"))
        await net.partition(false)
        try await peerB.sync.sync()
        try await peerA.sync.sync()
        try await net.converge()
        #expect(try await peerC.store.runningEntry()?.id == later.id)
        let adjustedA = await Self.adjusted(in: eventsA, until: peerA.store)
        #expect(adjustedA.map(\.reason) == [.stoppedByLaterStart])
        #expect(adjustedA.first?.causingDeviceID == peerB.test.deviceID)
        #expect(adjustedA.first?.before?.id == own.id)
        #expect(await Self.adjusted(in: eventsC, until: peerC.store).isEmpty)
    }

    /// The `.adjusted` events of `stream` up to a sentinel posted now.
    private static func adjusted(in stream: AsyncStream<StoreChange>, until store: TimeStore) async -> [EntryAdjustment] {
        store.publish(.error("sentinel"))
        var result: [EntryAdjustment] = []
        for await change in stream {
            if case let .adjusted(list) = change {
                result += list
            }
            if case .sync(.error("sentinel")) = change {
                break
            }
        }
        return result
    }
}

extension MultiStoreSyncTests {
    @Test("DATA-59 the start of day defaults to 00:00, syncs like any setting, and reaches every device's calendar")
    func startOfDaySyncs() async throws {
        let net = try await Network()
        let (peerA, peerB) = (net.peers[0], net.peers[1])
        #expect(peerB.store.displayCalendar().startOfDayHour == 0)
        try await peerA.store.set(.startOfDayHour, 4)
        try await net.converge()
        #expect(try await peerB.store.value(.startOfDayHour) == 4)
        #expect(peerB.store.displayCalendar().startOfDayHour == 4)
    }
}
