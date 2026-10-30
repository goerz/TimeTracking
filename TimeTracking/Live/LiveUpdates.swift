// LiveUpdates: the Mac app's live-update side: the sync coordinator,
// LiveStatePublisher, WidgetPushSender, the Device record, daily
// maintenance, and the copy of the agent's fallback block log
// (spec_data_and_sync.md §3.1, §4; spec_activity_tracking.md §4.1;
// spec_architecture.md §1.3).

import Foundation
import Observation
import os
import TimeTrackingCore

/// Runs sync and live updates while the app runs. A missing iCloud
/// container (ad-hoc builds) or account leaves sync stopped with an error
/// status; the store, the publisher, and the folder copy keep working.
@Observable
final class LiveUpdates {
    /// The period of the publisher, push, and folder-copy pass.
    static let interval: Duration = .seconds(2)

    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let coordinator: SyncCoordinator
    @ObservationIgnored let publisher: LiveStatePublisher
    @ObservationIgnored let sender: WidgetPushSender
    @ObservationIgnored private let pushClient: any WidgetPushing
    @ObservationIgnored private let readTrackerState: () async -> TrackerState?
    @ObservationIgnored private let mirror: ActivityFolderMirror?
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let confirmAccountSwitch: @Sendable () async -> Bool

    private(set) var syncStatus: SyncStatus = .idle
    private(set) var pushStatus: WidgetPushStatus = .idle(lastSentAt: nil)
    /// The last failure of the folder copy, if any.
    private(set) var mirrorError: String?

    /// Waits between ticks; tests replace it.
    @ObservationIgnored var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var lastRegistration: Date?
    @ObservationIgnored private var lastPurge: Date?
    private static let logger = Logging.logger(category: "Live")

    init(
        store: TimeStore,
        clock: any Clock,
        engineFactory: any SyncEngineFactory,
        pushClient: any WidgetPushing,
        readTrackerState: @escaping () async -> TrackerState?,
        mirror: ActivityFolderMirror?,
        deviceName: String,
        confirmAccountSwitch: @escaping @Sendable () async -> Bool
    ) {
        self.store = store
        self.clock = clock
        self.coordinator = SyncCoordinator(store: store, factory: engineFactory)
        self.publisher = LiveStatePublisher(store: store, deviceID: store.deviceID, clock: clock)
        self.sender = WidgetPushSender(store: store, client: pushClient, clock: clock)
        self.pushClient = pushClient
        self.readTrackerState = readTrackerState
        self.mirror = mirror
        self.deviceName = deviceName
        self.confirmAccountSwitch = confirmAccountSwitch
    }

    /// Registers the device, starts the coordinator, and with `looping`
    /// runs `tick()` every two seconds.
    func start(looping: Bool = true) async {
        let sender = sender
        await coordinator.onLiveState { event in await sender.handle(event) }
        await coordinator.onAccountSwitch(confirm: confirmAccountSwitch)
        await sender.onStatus { [weak self] status in
            Task { @MainActor in self?.pushStatus = status }
        }
        // Without a key, say so before the first push would.
        if await !pushClient.hasKey() {
            pushStatus = .noKey
        }
        let stream = store.changes
        statusTask = Task { [weak self] in
            for await change in stream {
                if case let .sync(status) = change {
                    self?.syncStatus = status
                }
            }
        }
        await tick()
        await coordinator.start()
        syncStatus = await coordinator.status
        guard looping else {
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await self?.sleep(Self.interval)
                guard !Task.isCancelled else {
                    return
                }
                await self?.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        statusTask?.cancel()
        statusTask = nil
        Task { [coordinator] in await coordinator.stop() }
    }

    /// One pass: the hourly `Device` record, the daily tombstone purge,
    /// this Mac's activity, due widget pushes, and the folder copy while the
    /// agent cannot write the iCloud container.
    func tick() async {
        let now = clock.now
        if lastRegistration.map({ now.timeIntervalSince($0) >= 3600 }) ?? true {
            lastRegistration = now
            do {
                try await store.registerDevice(name: deviceName, platform: .mac)
            } catch {
                Self.logger.error("Registering the device failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if lastPurge.map({ now.timeIntervalSince($0) >= 86_400 }) ?? true {
            lastPurge = now
            _ = try? await store.purgeExpiredTombstones()
        }
        let state = await readTrackerState()
        do {
            try await publisher.update(state)
        } catch {
            Self.logger.error("Publishing the activity failed: \(error.localizedDescription, privacy: .public)")
        }
        await sender.sendDue()
        await copyFolder(state)
    }

    /// The settings window's iCloud line.
    var syncStatusText: String {
        switch syncStatus {
        case .idle: "Up to date"
        case let .sending(count): "Sending \(count) change\(count == 1 ? "" : "s")…"
        case .fetching: "Receiving changes…"
        case .waitingForNetwork: "Waiting for the network"
        case .noAccount: "Not signed in to iCloud. Entries stay on this Mac."
        case let .error(message): message
        }
    }

    /// The settings window's widget updates line (spec_data_and_sync.md
    /// §4.3); a failure's detail goes to the log.
    var pushStatusText: String {
        switch pushStatus {
        case .noKey: "Every few minutes"
        case .idle(nil): "Instant"
        case let .idle(sent?): "Last sent at \(sent.formatted(date: .omitted, time: .shortened))"
        case .failing: "Not working"
        }
    }

    private func copyFolder(_ state: TrackerState?) async {
        guard let mirror, ActivityFolderMirror.isNeeded(for: state) else {
            return
        }
        do {
            _ = try await Task.detached { try mirror.sync() }.value
            mirrorError = nil
        } catch {
            if mirrorError == nil {
                Self.logger.error("Copying the block log failed: \(error.localizedDescription, privacy: .public)")
            }
            mirrorError = error.localizedDescription
        }
    }
}
