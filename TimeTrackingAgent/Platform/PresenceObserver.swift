// PresenceObserver: lock, sleep, display, user-switch, and app-activation
// notifications (spec_activity_tracking.md §2.1, §3.4).

import AppKit

/// Forwards `NSWorkspace` and screen-lock notifications as presence events,
/// and app activations as extra ticks.
@MainActor
final class PresenceObserver {
    private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []

    func start(event: @escaping @MainActor (PresenceEvent) -> Void, activation: @escaping @MainActor () -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, PresenceEvent)] = [
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.screensDidSleepNotification, .displaySleep),
            (NSWorkspace.screensDidWakeNotification, .displayWake),
            (NSWorkspace.sessionDidResignActiveNotification, .userSwitch),
            (NSWorkspace.sessionDidBecomeActiveNotification, .userReturn),
        ]
        for (name, kind) in events {
            observe(workspace, name) { event(kind) }
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { activation() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { event(.lock) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { event(.unlock) }
    }

    func stop() {
        for (center, token) in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { body() }
        }
        tokens.append((center, token))
    }
}
