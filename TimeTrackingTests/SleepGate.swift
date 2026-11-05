// SleepGate: a stand-in for Task.sleep in periodic loops, so a test steps
// a loop one period at a time without waiting (architecture.md §3).

import Foundation

/// Each `sleep` records its duration and suspends until `release()`.
@MainActor
final class SleepGate {
    private(set) var durations: [Duration] = []
    private var pending: CheckedContinuation<Void, any Error>?
    private var arrival: CheckedContinuation<Void, Never>?

    /// The loop's sleep.
    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
        arrival?.resume()
        arrival = nil
        try await withCheckedThrowingContinuation { pending = $0 }
    }

    /// Returns once the loop has called `sleep` `count` times in all.
    func waitForSleep(_ count: Int) async {
        while durations.count < count {
            await withCheckedContinuation { arrival = $0 }
        }
    }

    /// Ends the current sleep: one period has passed.
    func release() {
        pending?.resume()
        pending = nil
    }

    /// Ends the current sleep with cancellation, so the loop stops.
    func cancel() {
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}
