// URLEventHandler: receives `timetracking://` URLs as Apple events, so a
// start, stop, or continue does not bring the app forward (spec_automation.md §6).

import AppKit
import TimeTrackingCore

/// Installs the `kAEGetURL` handler and hands each URL to the `URLRouter`;
/// shows its alert with `NSAlert`.
final class URLEventHandler: NSObject {
    private var router: URLRouter?
    private var pending: [URL] = []
    /// The app that was frontmost before this one, to give the focus back.
    private var previousApp: NSRunningApplication?
    private var observer: (any NSObjectProtocol)?

    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, app != NSRunningApplication.current {
                    self?.previousApp = app
                }
            }
        }
    }

    /// Starts handling URLs, including those that arrived during launch.
    func attach(_ router: URLRouter) {
        router.alert = { message in
            let alert = NSAlert()
            alert.messageText = message
            alert.runModal()
        }
        self.router = router
        let urls = pending
        pending = []
        for url in urls {
            open(url)
        }
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, reply _: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text)
        else {
            return
        }
        open(url)
    }

    private func open(_ url: URL) {
        guard let router else {
            pending.append(url)
            return
        }
        let wasActive = NSApp.isActive
        let previous = previousApp
        Task {
            let outcome = await router.open(url)
            // Feedback for a start, stop, or continue is the menu bar and
            // the banner; the app that had the focus keeps it.
            if case .tracked = outcome, !wasActive, NSApp.isActive {
                previous?.activate()
            }
        }
    }
}
