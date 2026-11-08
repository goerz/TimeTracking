// TerminationSignal: stopping the agent cleanly when launchd sends SIGTERM
// at logout, shutdown, or unregistration (activity_tracking.md §5).

import Foundation

/// Runs a handler on the main actor when the process receives SIGTERM,
/// then exits.
///
/// The default action of SIGTERM ends the process at once; the agent
/// ignores the signal and handles it through a dispatch source instead,
/// so it can finish the running step first, for at most `limit`: a step
/// stuck in a call that doesn't return (an app that doesn't answer an
/// Apple event) would hold up an unregistration until launchd kills the
/// agent. Every write is atomic, so exiting mid-step loses nothing.
enum TerminationSignal {
    private static var source: (any DispatchSourceSignal)?
    /// How long the handler may take before the process exits anyway.
    static let limit: Duration = .seconds(5)

    /// Calls `handler` on the main actor on SIGTERM and exits with status 0
    /// when it returns or after `limit`.
    static func install(_ handler: @escaping @MainActor () async -> Void) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            Task.detached {
                try? await Task.sleep(for: limit)
                exit(0)
            }
            Task { @MainActor in
                await handler()
                exit(0)
            }
        }
        source.resume()
        Self.source = source
    }
}
