// CoordinatorSync: the library's SyncCoordinator with the CloudKit engine,
// as the iOS app drives it (spec_ios.md §7; spec_data_and_sync.md §3.1).

import Foundation
import TimeTrackingCore

/// Sync in the app process. After every applied fetch the widget timelines
/// and controls reload.
@MainActor
final class CoordinatorSync: SyncDriving {
    let coordinator: SyncCoordinator
    private let applied: @Sendable () async -> Void

    init(store: TimeStore, containerIdentifier: String, onApplied: @escaping @Sendable () async -> Void) {
        self.coordinator = SyncCoordinator(store: store, factory: CloudKitSyncEngineFactory(containerIdentifier: containerIdentifier))
        self.applied = onApplied
    }

    /// Registers the applied-fetch handler before the engine starts, so
    /// the first applied fetch already reloads the widgets.
    func start() async {
        await coordinator.onApplied(applied)
        await coordinator.start()
    }

    func stop() {
        Task { [coordinator] in await coordinator.stop() }
    }

    func fetchNow() async {
        await coordinator.fetchNow()
    }

    func sendNow() async {
        _ = await coordinator.drain()
        await coordinator.sendNow()
    }
}
