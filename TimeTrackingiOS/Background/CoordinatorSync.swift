// CoordinatorSync: the library's SyncCoordinator with the CloudKit engine,
// as the iOS app drives it (spec_ios.md §7; spec_data_and_sync.md §3.1).

import Foundation
import TimeTrackingCore

/// Sync in the app process. After every applied fetch the widget timelines
/// and controls reload.
@MainActor
final class CoordinatorSync: SyncDriving {
    let coordinator: SyncCoordinator

    init(store: TimeStore, containerIdentifier: String, onApplied: @escaping @Sendable () async -> Void) {
        self.coordinator = SyncCoordinator(store: store, factory: CloudKitSyncEngineFactory(containerIdentifier: containerIdentifier))
        Task { [coordinator] in await coordinator.onApplied(onApplied) }
    }

    func start() async {
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
