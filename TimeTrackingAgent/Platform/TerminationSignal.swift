// TerminationSignal: stopping the agent cleanly when launchd sends SIGTERM
// at logout, shutdown, or unregistration (spec_activity_tracking.md §2.8, §5).

import Foundation

/// Runs a handler on the main queue when the process receives SIGTERM, then exits.
///
/// The default action of SIGTERM ends the process at once; the agent
/// ignores the signal and handles it through a dispatch source instead,
/// so it can close today's open block first.
enum TerminationSignal {
    private static var source: (any DispatchSourceSignal)?

    /// Calls `handler` on the main actor on SIGTERM and exits with status 0.
    static func install(_ handler: @escaping @MainActor () -> Void) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                handler()
            }
            exit(0)
        }
        source.resume()
        Self.source = source
    }
}
