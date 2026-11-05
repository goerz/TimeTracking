// WidgetReloading: the widget reloads the iOS app model asks for, with a
// recording stand-in for tests and UI testing (ios.md §3, §5).

import Foundation

/// Reloads widget timelines and the timer control.
@MainActor
protocol WidgetReloading: AnyObject, Sendable {
    func reloadTimelines()
    func reloadControls()
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
