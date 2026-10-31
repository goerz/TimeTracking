// ShortcutsUpdating: Siri, Shortcuts, and Spotlight updates the iOS app
// model asks for, with a recording stand-in for tests and UI testing
// (spec_ios.md §6.2).

import Foundation
import TimeTrackingCore

/// Keeps Siri, Shortcuts, and Spotlight current with the project list.
@MainActor
protocol ShortcutsUpdating: AnyObject, Sendable {
    /// `updateAppShortcutParameters()` and the Spotlight index.
    func projectsChanged(_ projects: [ProjectRow])
    /// Donates a start or continue the user performed in the app.
    func donate(_ entry: TimeEntry)
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
