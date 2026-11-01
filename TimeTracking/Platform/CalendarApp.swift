// CalendarApp: opens an event in Calendar.app and names installed apps
// (spec_calendar.md §4.3, spec_activity.md §1.3).

import AppKit
import TimeTrackingCore

/// Calendar.app on the Mac.
enum CalendarApp {
    /// Shows the event's day in Calendar.app (EventKit has no deep link to an event).
    static func open(_ event: CalendarEvent) {
        let seconds = Int(event.start.timeIntervalSinceReferenceDate)
        if let url = URL(string: "ical://ekevent/\(seconds)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Names of installed apps.
enum InstalledApps {
    static func name(forBundleIdentifier identifier: String) -> String? {
        guard !identifier.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
