// TrackerOnboardingAlert: the first-launch alert with its "Open <APP_NAME> at
// login" checkbox (spec_timer_window.md §8.2). SwiftUI's dialog suppression
// toggle never wrote its binding back on the Mac, so this is an NSAlert whose
// suppression button is the checkbox.

import AppKit

/// Presents the alert as a sheet of the main window.
enum TrackerOnboardingAlert {
    static let text = "The tracker records which apps, sites, and terminal sessions you work in, "
        + "so the Calendar can suggest entries. It needs a few permissions."

    static func present(
        on window: NSWindow?,
        appName: String,
        opensAtLogin: Bool,
        answer: @escaping @MainActor (_ openSettings: Bool, _ opensAtLogin: Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Set up activity tracking?"
        alert.informativeText = text
        let open = alert.addButton(withTitle: "Open Tracker Settings")
        open.setAccessibilityIdentifier("onboarding.openTrackerSettings")
        let later = alert.addButton(withTitle: "Later")
        later.keyEquivalent = "\u{1b}"
        later.setAccessibilityIdentifier("onboarding.later")
        alert.showsSuppressionButton = true
        if let checkbox = alert.suppressionButton {
            checkbox.title = "Open \(appName) at login"
            checkbox.state = opensAtLogin ? .on : .off
            checkbox.setAccessibilityIdentifier("onboarding.openAtLogin")
        }
        let finish = { (response: NSApplication.ModalResponse) in
            answer(response == .alertFirstButtonReturn, alert.suppressionButton?.state == .on)
        }
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
