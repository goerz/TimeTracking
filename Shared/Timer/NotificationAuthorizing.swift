// NotificationAuthorizing: what the shared Timer model needs from each app's
// notifications: the permission request at the first start of an entry
// (spec_timer_window.md §10, spec_ios.md §8).

/// Requests notification permission; each app's notifier conforms.
@MainActor
protocol NotificationAuthorizing: AnyObject {
    /// Requests authorization once (at the first start of an entry).
    func requestAuthorization()
}
