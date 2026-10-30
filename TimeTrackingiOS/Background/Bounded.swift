// Bounded: runs work for at most a number of seconds without waiting for it
// to notice cancellation (spec_ios.md §4 item 3, §7 item 1).

import Foundation
import Synchronization

/// Waits for `work` or the timeout, whichever comes first; `work` keeps
/// running in the background when the timeout wins.
enum Bounded {
    /// Returns `true` when `work` finished in time.
    @discardableResult
    static func run(
        seconds: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        _ work: @escaping @Sendable () async -> Void
    ) async -> Bool {
        let resumed = Mutex(false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            @Sendable func finish(_ value: Bool) {
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first {
                    continuation.resume(returning: value)
                }
            }
            Task {
                await work()
                finish(true)
            }
            Task {
                await sleep(seconds)
                finish(false)
            }
        }
    }
}
