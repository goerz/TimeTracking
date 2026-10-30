// ChangeBroadcaster: fans store changes out to every subscriber (spec_data_and_sync.md §7.4).

import Foundation
import Synchronization

/// The subscribers of `StoreObserving.changes`; each access to `stream()`
/// adds one.
final class ChangeBroadcaster: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<StoreChange>.Continuation]>([:])

    func stream() -> AsyncStream<StoreChange> {
        let (stream, continuation) = AsyncStream<StoreChange>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { _ = $0.removeValue(forKey: id) }
        }
        return stream
    }

    func yield(_ change: StoreChange) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(change)
        }
    }

    func finish() {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.finish()
        }
    }
}
