// The Mac app's live-update side without CloudKit: degraded sync, the
// Device record, LiveState publication, and the block-log copy
// (spec_data_and_sync.md §3.1, §4; spec_activity_tracking.md §4.1).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

/// A factory that fails as CloudKit does without the container's entitlement.
private struct UnavailableFactory: SyncEngineFactory {
    func makeEngine(for _: SyncCoordinator, state _: Data?) throws -> any SyncEngineDriving {
        throw SyncTransportError.other("This build is not entitled to iCloud.")
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
        mirror: ActivityFolderMirror? = nil
    ) -> LiveUpdates {
        LiveUpdates(
            store: store,
            clock: clock,
            engineFactory: UnavailableFactory(),
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
        #expect(live.syncStatusText.contains("not entitled"))
        #expect(try await store.devices().map(\.name) == ["Test Mac"])
        let entry = try await store.start(projectID: nil, task: "Offline", at: clock.now)
        #expect(try await store.runningEntry()?.id == entry.id)
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
}
