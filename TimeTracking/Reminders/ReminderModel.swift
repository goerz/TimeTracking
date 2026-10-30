// ReminderModel: "Nothing is being tracked" reminders (spec_timer_window.md §7, §10).

import Foundation
import Observation
import TimeTrackingCore

/// Posts the `reminder` notification by the library's `ReminderSchedule`.
@Observable
final class ReminderModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let notifier: NotificationPosting
    @ObservationIgnored let settings: AppSettings
    /// Whether the session is locked.
    @ObservationIgnored var isLocked: () -> Bool = { false }

    /// The last reminder, which re-anchors the interval.
    private(set) var lastReminder: Date?
    private(set) var snoozedUntil: Date?
    /// When the app started watching (the anchor without any stop).
    @ObservationIgnored private let started: Date

    init(store: TimeStore, clock: any Clock, notifier: NotificationPosting, settings: AppSettings) {
        self.store = store
        self.clock = clock
        self.notifier = notifier
        self.settings = settings
        self.started = clock.now
    }

    /// Checks whether a reminder is due and posts it. Returns whether it posted.
    @discardableResult
    func check() async -> Bool {
        let schedule = settings.reminders
        guard schedule.isEnabled, !isLocked(), await (try? store.runningEntry()) == nil else {
            return false
        }
        let lastStop = try? await store.lastStoppedEntry(excluding: nil)
        let anchor = [lastStop?.end, lastReminder, started].compactMap(\.self).max() ?? started
        let now = clock.now
        guard schedule.isDue(at: now, anchor: anchor, snoozedUntil: snoozedUntil, calendar: .current) else {
            return false
        }
        lastReminder = now
        let body = lastStop?.end.map { "Last entry stopped at \(LocalDateText.time($0))." } ?? "Nothing has been tracked yet."
        notifier.post(NotificationRequest(category: .reminder, title: "Nothing is being tracked", body: body, sound: nil))
        return true
    }

    /// The next time to check, if reminders are on.
    func nextCheck() async -> Date? {
        let lastStop = try? await store.lastStoppedEntry(excluding: nil)
        let anchor = [lastStop?.end, lastReminder, started].compactMap(\.self).max() ?? started
        return settings.reminders.nextFire(after: anchor, snoozedUntil: snoozedUntil, calendar: .current)
    }

    /// The notification's Snooze action.
    func snooze() {
        snoozedUntil = clock.now + settings.reminders.snoozeInterval
        notifier.remove([.reminder])
    }
}
