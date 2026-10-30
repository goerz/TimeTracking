// The widget snapshot, its timeline end, the resolver, and the Mac activity
// line (spec_ios.md §2.3, §3, §4).

import Foundation
import Synchronization
import Testing
import TimeTrackingCore

/// Counts fetches and answers with a fixed state.
final class CountingLiveStateFetcher: LiveStateFetching {
    private let state: Mutex<(count: Int, record: SyncRecord?)>

    init(_ record: SyncRecord? = nil) {
        self.state = Mutex((0, record))
    }

    var count: Int {
        state.withLock { $0.count }
    }

    func fetch(_: SyncRecordRef) -> SyncRecord? {
        state.withLock { value in
            value.count += 1
            return value.record
        }
    }
}

func ephemeralShared() -> WidgetSharedState {
    WidgetSharedState(defaults: UserDefaults(suiteName: "WidgetTests." + UUID().uuidString) ?? .standard)
}

struct WidgetSnapshotTests {
    @Test("IOS-12 a timeline ends at the next midnight without a local Pomodoro and at the phase end with one")
    func reloadDate() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = try TestStore.date("2024-03-14T10:00", zone)
        let midnight = try TestStore.date("2024-03-15T00:00", zone)
        #expect(WidgetSnapshotBuilder.reloadDate(after: now, pomodoro: .off, timeZone: zone) == midnight)
        let end = now + 25 * 60
        #expect(WidgetSnapshotBuilder.reloadDate(after: now, pomodoro: .focus(end: end), timeZone: zone) == end)
        #expect(WidgetSnapshotBuilder.reloadDate(after: now, pomodoro: .onBreak(end: end), timeZone: zone) == end)
        #expect(WidgetSnapshotBuilder.reloadDate(after: now, pomodoro: .focusOver(end: now - 60), timeZone: zone) == midnight)
    }

    @Test("IOS-12 a snapshot carries its timeline end and the local Pomodoro")
    func snapshotReload() async throws {
        let test = try await TestStore()
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: test.zone)
        let end = test.clock.now + 600
        let snapshot = await builder.build(at: test.clock.now, live: LiveState(), setupComplete: true, pomodoro: .focus(end: end))
        #expect(snapshot.reloadAt == end)
        #expect(snapshot.pomodoro == .focus(end: end))
    }

    @Test("IOS-7 the Now widget counts from the chain start; at 00:30 the Today total holds 0:30:00 of an entry started at 23:00")
    func chainStartAndToday() async throws {
        let test = try await TestStore(now: "2024-03-14T23:00")
        let made = try await test.structure(projects: ["Paper"])
        let started = try test.date("2024-03-14T23:00")
        _ = try await test.store.start(projectID: made.projects[0].id, task: "Draft", at: started)
        _ = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Earlier",
            start: test.date("2024-03-14T09:00"),
            end: test.date("2024-03-14T10:00")
        ))
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: test.zone)
        let before = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        #expect(before.running?.chainStart == started)
        #expect(before.todaySeconds(at: test.clock.now) == 3600)

        try test.clock.set(test.date("2024-03-15T00:30"))
        try await test.store.checkInvariants()
        let after = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        let running = try #require(after.running)
        #expect(running.chainStart == started)
        #expect(DurationText.clock(Int(test.clock.now.timeIntervalSince(running.chainStart))) == "1:30:00")
        #expect(after.todaySeconds(at: test.clock.now) == 1800)
        #expect(after.relevance == 100)
    }

    @Test(
        "IOS-14 the Pinned widget shows pinnedProjectIDs by default, an explicit list when configured; the running project's button stops"
    )
    func pinned() async throws {
        let test = try await TestStore()
        let made = try await test.structure(projects: ["A", "B", "C"])
        let ids = made.projects.map(\.id)
        try await test.store.set(.pinnedProjectIDs, [ids[1], ids[0]])
        _ = try await test.store.create(EntryDraft(
            projectID: ids[1],
            task: "Old task",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T08:30")
        ))
        _ = try await test.store.start(projectID: ids[0], task: "Now", at: test.date("2024-03-14T09:00"))
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: test.zone)
        let live = try await test.store.liveState()

        let byDefault = await builder.build(at: test.clock.now, live: live, setupComplete: true)
        #expect(byDefault.pinned.map(\.projectID) == [ids[1], ids[0]])
        #expect(byDefault.pinned.map(\.isRunning) == [false, true])
        #expect(byDefault.pinned[0].task == "Old task")

        let explicit = await builder.build(at: test.clock.now, live: live, setupComplete: true, pinnedIDs: [ids[2]], taskMode: .blank)
        #expect(explicit.pinned.map(\.projectID) == [ids[2]])
        #expect(explicit.pinned[0].task.isEmpty)

        try await test.store.archive(ids[2])
        let archived = await builder.build(at: test.clock.now, live: live, setupComplete: true, pinnedIDs: [ids[2]])
        #expect(archived.pinned[0].isArchived)
    }

    @Test("IOS-11 the Recent rows leave out the running pair; after a stop the snapshot is idle with the latest entry")
    func recentAndIdle() async throws {
        let test = try await TestStore()
        let made = try await test.structure(projects: ["A", "B"])
        _ = try await test.store.create(EntryDraft(
            projectID: made.projects[1].id,
            task: "Read",
            start: test.date("2024-03-14T07:00"),
            end: test.date("2024-03-14T07:30")
        ))
        _ = try await test.store.start(projectID: made.projects[0].id, task: "Write", at: test.date("2024-03-14T09:00"))
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: test.zone)
        let running = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        #expect(running.recent.map(\.task) == ["Read"])
        #expect(running.running?.row.projectName == "A")
        #expect(running.running?.row.clientName == made.client.name)

        _ = try await test.store.stop(at: test.clock.now)
        let idle = try await builder.build(at: test.clock.now, live: test.store.liveState(), setupComplete: true)
        #expect(idle.running == nil)
        #expect(idle.latest?.task == "Write")
        #expect(idle.todaySeconds(at: test.clock.now) == 3600 + 1800)
        #expect(idle.relevance == 60)
    }

    @Test("Before the first sync every widget asks to finish setup")
    func needsSetup() async {
        let builder = WidgetSnapshotBuilder(store: nil, timeZone: .gmt)
        let snapshot = await builder.build(at: Date(timeIntervalSince1970: 0), live: LiveState(), setupComplete: false)
        #expect(snapshot.needsSetup)
    }

    @Test("IOS-16 a provider shows a LiveState running entry the store does not hold yet and reports the change for the control")
    func unknownRunningEntry() async throws {
        let server = InMemorySyncServer()
        let mac = try await TestStore(deviceID: DeviceID())
        let made = try await mac.structure(projects: ["Paper"])
        let entry = try await mac.store.start(projectID: made.projects[0].id, task: "Draft", at: mac.clock.now)
        try await StoreSynchronizer(store: mac.store, transport: server.transport(for: "mac")).sync()

        let phone = try await TestStore()
        let resolver = WidgetLiveResolver(
            shared: ephemeralShared(),
            reader: LiveStateReader(transport: server.transport(for: "phone")),
            clock: phone.clock
        )
        let resolution = try await resolver.resolve(local: phone.store.liveState())
        #expect(resolution.fetched)
        #expect(resolution.runningChanged)
        let snapshot = await WidgetSnapshotBuilder(store: phone.store, timeZone: phone.zone)
            .build(at: phone.clock.now, live: resolution.liveState, setupComplete: true)
        #expect(snapshot.running?.entryID == entry.id)
        #expect(snapshot.running?.row.projectName == "Paper")
        #expect(snapshot.running?.row.task == "Draft")
    }

    @Test("IOS-17 providers within 10 s of a fetch or 5 s of the app's own write do not fetch")
    func reuse() async {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_000_000))
        let shared = ephemeralShared()
        let fetcher = CountingLiveStateFetcher()
        let resolver = WidgetLiveResolver(shared: shared, reader: LiveStateReader(transport: fetcher), clock: clock)
        _ = await resolver.resolve(local: nil)
        #expect(fetcher.count == 1)
        clock.advance(by: 9)
        let reused = await resolver.resolve(local: nil)
        #expect(!reused.fetched)
        #expect(fetcher.count == 1)
        clock.advance(by: 2)
        _ = await resolver.resolve(local: nil)
        #expect(fetcher.count == 2)

        clock.advance(by: 20)
        shared.recordAppWrite(LiveState(), at: clock.now)
        clock.advance(by: 4)
        _ = await resolver.resolve(local: nil)
        #expect(fetcher.count == 2)
        clock.advance(by: 2)
        _ = await resolver.resolve(local: nil)
        #expect(fetcher.count == 3)
    }

    @Test("IOS-15 the shared state keeps the widget push token, nil when no widget is installed")
    func pushToken() {
        let shared = ephemeralShared()
        #expect(shared.pushToken == nil)
        shared.pushToken = .some(Data([0xAB, 0x01]).hexString)
        #expect(shared.pushToken == .some("ab01"))
        shared.pushToken = .some(nil)
        #expect(shared.pushToken == .some(nil))
    }

    @Test("The Mac activity line: running trackers only, newest first, at most two; the subject alone for plain apps")
    func macLines() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let since = try TestStore.date("2024-03-14T14:02", zone)
        func activity(
            _ device: String,
            _ primary: TrackerPrimaryItem?,
            _ presence: String,
            running: Bool = true,
            at offset: TimeInterval
        ) -> LiveState.MacActivity {
            LiveState.MacActivity(
                device: device,
                primary: primary,
                groupKey: nil,
                presence: presence,
                since: since,
                agentRunning: running,
                lastTick: nil,
                health: [],
                updatedAt: since + offset
            )
        }
        let state = LiveState(activity: [
            "a": activity("MacBook", TrackerPrimaryItem(context: "tmux:paper", subject: "draft"), "active", at: 10),
            "b": activity("iMac", TrackerPrimaryItem(context: "skim", subject: "notes.pdf"), "idle", at: 20),
            "c": activity("Old", nil, "active", running: false, at: 30),
            "d": activity("Mini", nil, "asleep", at: 0),
        ])
        #expect(MacActivityLine.lines(state, timeZone: zone) == [
            "iMac · notes.pdf · idle since 14:02",
            "MacBook · paper (tmux) · draft",
        ])
        let words = LiveState(activity: [
            "a": activity("A", TrackerPrimaryItem(context: "skim", subject: ""), "passive", at: 3),
            "b": activity("B", nil, "other_user", at: 2),
            "c": activity("C", nil, "locked", at: 1),
        ])
        #expect(MacActivityLine.lines(words, timeZone: zone, limit: 3) == [
            "A · Skim · in use",
            "B · another user since 14:02",
            "C · locked since 14:02",
        ])
    }
}
