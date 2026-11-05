// SyncDriving: the sync engine as the iOS app model drives it, with a
// stand-in over the library's synchronizer for tests (ios.md §7).

import Foundation
import TimeTrackingCore

/// The sync engine as the app drives it.
@MainActor
protocol SyncDriving: AnyObject, Sendable {
    func start() async
    func stop()
    /// Fetches the server's changes now.
    func fetchNow() async
    /// Sends the pending changes now.
    func sendNow() async
}

/// Sync over the library's `StoreSynchronizer` and an in-memory server
/// (tests): each call runs one full sync; a failure publishes the status.
@MainActor
final class SynchronizerSync: SyncDriving {
    let synchronizer: StoreSynchronizer
    let store: TimeStore
    private(set) var fetches = 0

    init(store: TimeStore, transport: any SyncTransport) {
        self.store = store
        self.synchronizer = StoreSynchronizer(store: store, transport: transport)
    }

    func start() async {
        await sync()
    }

    func stop() {}

    func fetchNow() async {
        fetches += 1
        await sync()
    }

    func sendNow() async {
        await sync()
    }

    private func sync() async {
        do {
            try await synchronizer.sync()
            store.publish(.idle)
        } catch {
            store.publish(.waitingForNetwork)
        }
    }
}
