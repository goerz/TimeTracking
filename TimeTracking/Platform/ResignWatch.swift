// ResignWatch: runs an action once if the app resigns active right after
// switching to the accessory policy (spec_menubar.md §4).

import AppKit

/// Waits up to 300 ms for `NSApplication.didResignActiveNotification`
/// and then, on the next turn of the run loop, runs the action once. A
/// switch to accessory deactivates the app asynchronously, sometimes after
/// the app has already asked to stay active, so `ActivationPolicy` takes
/// activation back once the deactivation has happened.
@MainActor
final class ResignWatch {
    /// How long after the switch a deactivation counts as caused by it:
    /// the deactivation follows within about 150 ms, and a user switching
    /// to another app on purpose takes longer, so their switch stands.
    static let window = Duration.milliseconds(300)

    /// The running watch; a new one replaces it.
    private static var current: ResignWatch?

    private var token: (any NSObjectProtocol)?
    private let action: () -> Void

    private init(action: @escaping () -> Void) {
        self.action = action
    }

    static func start(_ action: @escaping () -> Void) {
        current?.stop()
        let watch = ResignWatch(action: action)
        current = watch
        watch.token = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak watch] _ in
            MainActor.assumeIsolated { watch?.fire() }
        }
        Task { [weak watch] in
            try? await Task.sleep(for: Self.window)
            watch?.stop()
        }
    }

    private func fire() {
        stop()
        // After AppKit has finished deactivating.
        DispatchQueue.main.async { [action] in
            MainActor.assumeIsolated { action() }
        }
    }

    private func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
        if Self.current === self {
            Self.current = nil
        }
    }
}
