// SilentPushHandler: a CloudKit silent push wakes the app (ios.md §7
// item 1): pass it to the engine, wait at most 25 s, run the fan-out, and
// call the completion handler exactly once.

import Foundation

/// What the remote-notification handler does; the app delegate calls it.
@MainActor
struct SilentPushHandler {
    /// The longest wait for the engine's fetch.
    nonisolated static let timeout: TimeInterval = 25

    /// Fetches the changes the push announced.
    var fetch: @Sendable () async -> Void
    /// The fan-out of §7 item 4 (and the token upload).
    var fanOut: () async -> Void
    /// Waits; replaced in tests.
    var sleep: @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }

    /// Handles one push; `completion` receives whether new data arrived in time.
    func handle(completion: (Bool) -> Void) async {
        let inTime = await Bounded.run(seconds: Self.timeout, sleep: sleep, fetch)
        await fanOut()
        completion(inTime)
    }
}
