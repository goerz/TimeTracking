// Broadcaster: fans changes out to every subscriber of a change stream
// (data_and_sync.md §7.4).

import Foundation
import Synchronization

/// The subscribers of a change stream; each call of `stream()` adds one.
final class Broadcaster<Element: Sendable>: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Element>.Continuation]>([:])
    private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy

    /// Each stream keeps the newest 256 elements unless `bufferingPolicy` says otherwise.
    init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(256)) {
        self.bufferingPolicy = bufferingPolicy
    }

    func stream() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { _ = $0.removeValue(forKey: id) }
        }
        return stream
    }

    func yield(_ element: Element) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(element)
        }
    }

    func finish() {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.finish()
        }
    }
}

/// The subscribers of `StoreObserving.changes`.
typealias ChangeBroadcaster = Broadcaster<StoreChange>
