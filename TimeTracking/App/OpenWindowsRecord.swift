// OpenWindowsRecord: the main window and the Mini Timer as open when the
// app last quit, for the next login-item launch (spec_timer.md §1.3).

import Foundation
import TimeTrackingCore

/// The device setting `openWindows`, kept current as the windows open and
/// close, so it holds the windows open at quit also after a crash or a
/// force quit. From the start of a quit it no longer changes: the windows
/// that close while the app terminates stay recorded.
///
/// The app keeps this record itself instead of using macOS state
/// restoration: restoration applies at every launch, not only at login,
/// and saved state is what made SwiftUI skip the launch window (see
/// `TimeTrackingApp`). As a consequence, the shutdown dialog's "Reopen
/// windows when logging back in" doesn't affect this app.
final class OpenWindowsRecord {
    private let device: DeviceSettings
    private var frozen = false

    init(device: DeviceSettings) {
        self.device = device
    }

    /// The windows open now, or when the app last quit.
    var windows: Set<LaunchWindow> {
        device[.openWindows]
    }

    /// A launch starts with no window open: returns what was open when the
    /// app last quit and clears the record.
    func takeOpenAtQuit() -> Set<LaunchWindow> {
        let windows = windows
        device[.openWindows] = []
        return windows
    }

    func opened(_ window: LaunchWindow) {
        update { $0.insert(window) }
    }

    func closed(_ window: LaunchWindow) {
        update { $0.remove(window) }
    }

    /// The app is quitting.
    func freeze() {
        frozen = true
    }

    private func update(_ change: (inout Set<LaunchWindow>) -> Void) {
        guard !frozen else {
            return
        }
        var windows = windows
        change(&windows)
        if windows != self.windows {
            device[.openWindows] = windows
        }
    }
}
