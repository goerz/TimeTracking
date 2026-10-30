// PhoneServices: the system services the iOS app model calls, as protocols
// with recording stand-ins for tests and UI testing (spec_ios.md §3, §5,
// §6.2, §7, §9.6).

import Foundation
import TimeTrackingCore

/// Reloads widget timelines and the timer control.
@MainActor
protocol WidgetReloading: AnyObject, Sendable {
    func reloadTimelines()
    func reloadControls()
}

/// Keeps Siri, Shortcuts, and Spotlight current with the project list.
@MainActor
protocol ShortcutsUpdating: AnyObject, Sendable {
    /// `updateAppShortcutParameters()` and the Spotlight index.
    func projectsChanged(_ projects: [ProjectRow])
    /// Donates a start or continue the user performed in the app.
    func donate(_ entry: TimeEntry)
}

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

/// The flush of the activity collection file (spec_ios.md §9.6); step 8b
/// supplies the real one.
@MainActor
protocol CollectionFlushing: AnyObject, Sendable {
    /// Flushes when the last flush is more than 5 minutes old.
    func flushIfDue() async
}

/// Records reloads (tests, UI testing).
@MainActor
final class RecordingWidgetReloader: WidgetReloading {
    private(set) var timelineReloads = 0
    private(set) var controlReloads = 0

    func reloadTimelines() {
        timelineReloads += 1
    }

    func reloadControls() {
        controlReloads += 1
    }
}

/// Records shortcut updates and donations (tests, UI testing).
@MainActor
final class RecordingShortcuts: ShortcutsUpdating {
    private(set) var updates = 0
    private(set) var donations: [TimeEntry] = []

    func projectsChanged(_: [ProjectRow]) {
        updates += 1
    }

    func donate(_ entry: TimeEntry) {
        donations.append(entry)
    }
}

/// No collection yet (step 8b): nothing to flush.
@MainActor
final class NoCollection: CollectionFlushing {
    private(set) var flushes = 0

    func flushIfDue() {
        flushes += 1
    }
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
