// The Mac app's live-update side without CloudKit: degraded sync, the
// fetches on activation and every 30 seconds, the Device record, LiveState
// publication, and the block-log copy (spec_data_and_sync.md §3.1, §4;
// spec_activity_tracking.md §4.1).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

/// A factory that fails as CloudKit does without the container's entitlement.
private struct UnavailableFactory: SyncEngineFactory {
    func makeEngine(for _: SyncCoordinator, state _: Data?) throws -> any SyncEngineDriving {
        throw SyncTransportError.notEntitled
    }
}

/// An engine that only counts the fetches asked of it.
private actor CountingEngine: SyncEngineDriving {
    private(set) var fetches = 0

    func addPending(_ changes: [SyncPendingChange]) -> Int {
        changes.count
    }

    func removePending(_: [SyncPendingChange]) {}
    func addZone() {}
    func sendChanges() {}

    func fetchChanges() {
        fetches += 1
    }
}

private struct CountingFactory: SyncEngineFactory {
    let engine: CountingEngine

    func makeEngine(for _: SyncCoordinator, state _: Data?) -> any SyncEngineDriving {
        engine
    }
}

/// A push client without a key.
private struct NoKeyClient: WidgetPushing {
    func hasKey() -> Bool {
        false
    }

    func pushWidgets(to _: String) throws(PushError) -> APNsResponse {
        throw .noKey
    }
}

@MainActor
struct LiveUpdatesTests {
    private static func state(sharedFolder: TrackerSourceStatus, reason: String, at time: Date) -> TrackerState {
        TrackerState(
            device: "macbook",
            openBlock: nil,
            primary: TrackerPrimaryItem(context: "tmux:paper", subject: "draft", detail: "nvim"),
            presence: TrackerPresence(state: .active, since: time),
            health: TrackerHealth(lastTick: time, version: "1.0", sources: [
                TrackerSourceHealth(id: "shared_folder", name: "iCloud Drive folder", status: sharedFolder, reason: reason),
            ])
        )
    }

    private static func live(
        store: TimeStore,
        clock: ManualClock,
        state: TrackerState?,
        mirror: ActivityFolderMirror? = nil,
        engineFactory: any SyncEngineFactory = UnavailableFactory()
    ) -> LiveUpdates {
        LiveUpdates(
            store: store,
            clock: clock,
            engineFactory: engineFactory,
            pushClient: NoKeyClient(),
            readTrackerState: { state },
            mirror: mirror,
            deviceName: "Test Mac",
            confirmAccountSwitch: { false }
        )
    }

    @Test("without an iCloud container sync reports an error, the device registers, and writes work locally")
    func degradesWithoutCloudKit() async throws {
        let clock = ManualClock.fixture()
        let store = try await TimeStore.inMemory(clock: clock)
        let live = Self.live(store: store, clock: clock, state: nil)
        await live.start(looping: false)
        guard case .error = live.syncStatus else {
            Issue.record("expected an error status, got \(live.syncStatus)")
            return
        }
        #expect(await live.coordinator.isRunning == false)
        #expect(live.syncStatusText == "This copy of the app can't use iCloud.")
        #expect(live.pushStatusText == "Off (no push key)")
        #expect(try await store.devices().map(\.name) == ["Test Mac"])
        let entry = try await store.start(projectID: nil, task: "Offline", at: clock.now)
        #expect(try await store.runningEntry()?.id == entry.id)
        live.stop()
    }

    @Test("DATA-49 the Mac fetches when it becomes active and 30 seconds after the last fetch, one at a time")
    func fetchesOnActivationAndPeriodically() async throws {
        let clock = ManualClock.fixture()
        let store = try await TimeStore.inMemory(clock: clock)
        let engine = CountingEngine()
        let live = Self.live(store: store, clock: clock, state: nil, engineFactory: CountingFactory(engine: engine))
        // Before sync starts there is nothing to fetch with.
        live.activated()
        await live.waitForFetch()
        await live.start(looping: false)
        #expect(await engine.fetches == 0)

        clock.advance(by: 29)
        await live.tick()
        await live.waitForFetch()
        #expect(await engine.fetches == 0)
        clock.advance(by: 1)
        await live.tick()
        await live.waitForFetch()
        #expect(await engine.fetches == 1)

        // Activation fetches at once and restarts the 30-second period.
        clock.advance(by: 10)
        live.activated()
        await live.waitForFetch()
        #expect(await engine.fetches == 2)
        clock.advance(by: 29)
        await live.tick()
        await live.waitForFetch()
        #expect(await engine.fetches == 2)
        clock.advance(by: 1)
        await live.tick()
        await live.waitForFetch()
        #expect(await engine.fetches == 3)

        // A request while a fetch is in flight joins it.
        live.activated()
        live.activated()
        await live.waitForFetch()
        #expect(await engine.fetches == 4)
        live.stop()
    }

    @Test("DATA-34 a tick publishes this Mac's activity from current.json into LiveState")
    func publishesActivity() async throws {
        let clock = ManualClock.fixture()
        let store = try await TimeStore.inMemory(clock: clock)
        let state = Self.state(sharedFolder: .active, reason: "", at: clock.now)
        let live = Self.live(store: store, clock: clock, state: state)
        await live.tick()
        let activity = try await store.liveState().activity[store.deviceID.rawValue]
        #expect(activity?.device == "macbook")
        #expect(activity?.agentRunning == true)
        #expect(activity?.primary?.subject == "draft")
    }

    @Test("TRK-20 while the agent cannot write the container, a tick copies the local block log and settings into it")
    func copiesFallbackLog() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "tt-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appending(path: "local")
        let container = root.appending(path: "container")
        try FileManager.default.createDirectory(at: local.appending(path: "blocks"), withIntermediateDirectories: true)
        let month = local.appending(path: "blocks/2024-03.jsonl")
        try Data("{\"format\":1}\n".utf8).write(to: month)
        try Data("[blocks]\n".utf8).write(to: local.appending(path: "settings.toml"))
        let clock = ManualClock.fixture()
        let store = try await TimeStore.inMemory(clock: clock)
        let mirror = ActivityFolderMirror(local: local, container: container)
        let copied = container.appending(path: "blocks/2024-03.jsonl")

        let active = Self.live(
            store: store,
            clock: clock,
            state: Self.state(sharedFolder: .active, reason: "", at: clock.now),
            mirror: mirror
        )
        await active.tick()
        #expect(!FileManager.default.fileExists(atPath: copied.path))
        // Without iCloud Drive the folder reports `off`: nothing to copy into.
        let offState = Self.state(sharedFolder: .off, reason: "iCloud Drive is off; activity stays on this Mac", at: clock.now)
        await Self.live(store: store, clock: clock, state: offState, mirror: mirror).tick()
        #expect(!FileManager.default.fileExists(atPath: copied.path))

        let state = Self.state(sharedFolder: .fallback, reason: ActivityFolderMirror.fallbackReason, at: clock.now)
        let fallback = Self.live(store: store, clock: clock, state: state, mirror: mirror)
        await fallback.tick()
        #expect(try Data(contentsOf: copied) == Data(contentsOf: month))
        #expect(FileManager.default.fileExists(atPath: container.appending(path: "settings.toml").path))
        try Data("{\"format\":1}\n{\"s\":\"2024-03-14T09:00:00\"}\n".utf8).write(to: month)
        await fallback.tick()
        #expect(try Data(contentsOf: copied) == Data(contentsOf: month))
        #expect(fallback.mirrorError == nil)
    }

    @Test("TRK-20 the running app's loop copies each append into the container one 2-second period later, within 5 seconds")
    func copyLoop() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "tt-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appending(path: "local")
        let container = root.appending(path: "container")
        try FileManager.default.createDirectory(at: local.appending(path: "blocks"), withIntermediateDirectories: true)
        let month = local.appending(path: "blocks/2024-03.jsonl")
        try Data("{\"format\":1}\n".utf8).write(to: month)
        let clock = ManualClock.fixture()
        let store = try await TimeStore.inMemory(clock: clock)
        let state = Self.state(sharedFolder: .fallback, reason: ActivityFolderMirror.fallbackReason, at: clock.now)
        let live = Self.live(store: store, clock: clock, state: state, mirror: ActivityFolderMirror(local: local, container: container))
        let gate = SleepGate()
        live.sleep = { try await gate.sleep($0) }
        let copied = container.appending(path: "blocks/2024-03.jsonl")
        await live.start(looping: true)
        #expect(try Data(contentsOf: copied) == Data(contentsOf: month))
        for line in 1 ... 2 {
            await gate.waitForSleep(line)
            let lines = "{\"format\":1}\n" + String(repeating: "{\"s\":\"2024-03-14T09:00:00\"}\n", count: line)
            try Data(lines.utf8).write(to: month)
            #expect(try Data(contentsOf: copied) != Data(contentsOf: month))
            gate.release()
            await gate.waitForSleep(line + 1)
            #expect(try Data(contentsOf: copied) == Data(contentsOf: month))
        }
        #expect(gate.durations.allSatisfy { $0 == LiveUpdates.interval })
        #expect(LiveUpdates.interval <= .seconds(5))
        live.stop()
        gate.cancel()
    }
}
