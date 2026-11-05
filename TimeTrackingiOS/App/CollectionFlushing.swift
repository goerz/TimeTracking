// CollectionFlushing: the activity collection flush the iOS app model
// drives, with a recording stand-in for tests (ios.md §9.6, §9.7).

import Foundation

/// The flush of the activity collection file and the app's own lines
/// (ios.md §9.6, §9.7); `CollectionModel` is the real one.
@MainActor
protocol CollectionFlushing: AnyObject, Sendable {
    /// Flushes when the last flush is more than 5 minutes old (wrapper
    /// intents and the fan-out).
    func flushIfDue() async
    /// Flushes now (foreground, CloudKit push, refresh task, "Flush Now").
    func flush() async
    /// The scene moved to the foreground or the background.
    func appMoved(toForeground foreground: Bool) async
}

/// Records the calls without collecting (tests that do not look at the
/// collection).
@MainActor
final class NoCollection: CollectionFlushing {
    private(set) var flushes = 0
    private(set) var dueChecks = 0
    private(set) var transitions: [Bool] = []

    func flushIfDue() {
        dueChecks += 1
    }

    func flush() {
        flushes += 1
    }

    func appMoved(toForeground foreground: Bool) {
        transitions.append(foreground)
    }
}
