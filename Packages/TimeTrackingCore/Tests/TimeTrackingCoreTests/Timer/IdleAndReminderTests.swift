// Idle detection and reminders (spec_timer_window.md §6, §7), and the tracker
// warning rule (spec_menubar.md §3).

import Foundation
import Testing
import TimeTrackingCore

struct IdleAndReminderTests {
    let zone = TimeZone(identifier: "Europe/Berlin") ?? .current

    func date(_ text: String) throws -> Date {
        try #require(LaunchArguments.parseInstant(text, timeZone: zone))
    }

    @Test(
        "TW-27 10 min 5 s without input prompts with the time input stopped; not passive, idle, or short"
    )
    func idlePrompt() throws {
        var detector = IdleDetector()
        let stopped = try date("2024-03-14T14:02")
        // Samples every 10 s while input is absent.
        #expect(detector.sample(idleSeconds: 300, at: stopped + 300, isRunning: true) == nil)
        #expect(detector.sample(idleSeconds: 605, at: stopped + 605, isRunning: true) == nil)
        // Input resumes.
        #expect(detector.sample(idleSeconds: 1, at: stopped + 616, isRunning: true) == .prompt(idleStart: stopped))

        // Below the threshold: no prompt.
        var short = IdleDetector()
        #expect(short.sample(idleSeconds: 590, at: stopped + 590, isRunning: true) == nil)
        #expect(short.sample(idleSeconds: 1, at: stopped + 600, isRunning: true) == nil)

        // Nothing running: no prompt.
        var idle = IdleDetector()
        #expect(idle.sample(idleSeconds: 700, at: stopped + 700, isRunning: false) == nil)
        #expect(idle.sample(idleSeconds: 1, at: stopped + 710, isRunning: false) == nil)

        // Passive presence from the tracker: no prompt.
        var passive = IdleDetector()
        let watching = TrackerPresence(state: .passive, since: stopped)
        #expect(passive.sample(idleSeconds: 700, at: stopped + 700, isRunning: true, presence: watching) == nil)
        #expect(passive.sample(idleSeconds: 1, at: stopped + 710, isRunning: true, presence: watching) == nil)

        // A threshold of 20 minutes ignores 10.
        var twenty = IdleDetector(settings: IdleSettings(thresholdMinutes: 20))
        _ = twenty.sample(idleSeconds: 700, at: stopped + 700, isRunning: true)
        #expect(twenty.sample(idleSeconds: 1, at: stopped + 710, isRunning: true) == nil)
    }

    @Test("TW-29 lock, sleep, and shutdown follow the settings, using the lock or shutdown time")
    func lockSleepShutdown() throws {
        let lock = try date("2024-03-14T12:00")
        // Ask when I return: prompt at the lock time.
        var ask = IdleDetector()
        #expect(ask.event(.lock, at: lock, isRunning: true) == nil)
        #expect(ask.sample(idleSeconds: 30, at: lock + 30, isRunning: true) == nil)
        #expect(ask.event(.unlock, at: lock + 1800, isRunning: true) == nil)
        #expect(ask.sample(idleSeconds: 2, at: lock + 1802, isRunning: true) == .prompt(idleStart: lock))

        // Stop the entry at that moment.
        var stop = IdleDetector(settings: IdleSettings(onLockOrSleep: .stop))
        #expect(stop.event(.sleep, at: lock, isRunning: true) == .stop(at: lock))
        _ = stop.event(.wake, at: lock + 1800, isRunning: false)
        #expect(stop.sample(idleSeconds: 1, at: lock + 1801, isRunning: false) == nil)

        // Keep tracking: no prompt for an absence with a lock.
        var keep = IdleDetector(settings: IdleSettings(onLockOrSleep: .keep))
        #expect(keep.event(.lock, at: lock, isRunning: true) == nil)
        _ = keep.event(.unlock, at: lock + 1800, isRunning: true)
        #expect(keep.sample(idleSeconds: 1, at: lock + 1801, isRunning: true) == nil)

        // The tracker's locked presence supplies the exact since.
        var presence = IdleDetector()
        let locked = TrackerPresence(state: .locked, since: lock - 20)
        _ = presence.sample(idleSeconds: 50, at: lock + 30, isRunning: true, presence: locked)
        #expect(presence.sample(idleSeconds: 1, at: lock + 900, isRunning: true) == .prompt(idleStart: lock - 20))

        // Shutdown stops at the shutdown time when the setting is on.
        var shutdown = IdleDetector()
        #expect(shutdown.event(.shutdown, at: lock, isRunning: true) == .stop(at: lock))
        var noStop = IdleDetector(settings: IdleSettings(stopOnShutdown: false))
        #expect(noStop.event(.shutdown, at: lock, isRunning: true) == nil)
    }

    @Test(
        "TW-30 reminders every 10 min, 09:00 to 17:00, weekdays: fire after a Tuesday stop, not at 17:05 or Saturday; Snooze"
    )
    func reminders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let schedule = ReminderSchedule(isEnabled: true)
        // 2024-03-12 is a Tuesday.
        let stop = try date("2024-03-12T10:00")
        #expect(schedule.nextFire(after: stop, snoozedUntil: nil, calendar: calendar) == stop + 600)
        #expect(!schedule.isDue(at: stop + 599, anchor: stop, snoozedUntil: nil, calendar: calendar))
        #expect(schedule.isDue(at: stop + 600, anchor: stop, snoozedUntil: nil, calendar: calendar))
        // 17:05 is outside the hours; Saturday is not selected.
        let late = try date("2024-03-12T16:58")
        #expect(try !schedule.isDue(
            at: date("2024-03-12T17:05"),
            anchor: late,
            snoozedUntil: nil,
            calendar: calendar
        ))
        let saturday = try date("2024-03-16T11:00")
        #expect(!schedule.isDue(
            at: saturday,
            anchor: saturday - 3600,
            snoozedUntil: nil,
            calendar: calendar
        ))
        // After Friday 16:58 the next reminder is Monday 09:00.
        let friday = try date("2024-03-15T16:58")
        #expect(try schedule.nextFire(after: friday, snoozedUntil: nil, calendar: calendar) == date("2024-03-18T09:00"))
        // Snooze for 60 minutes.
        let snoozed = stop + 600 + schedule.snoozeInterval
        #expect(!schedule.isDue(
            at: stop + 1800,
            anchor: stop + 600,
            snoozedUntil: snoozed,
            calendar: calendar
        ))
        #expect(schedule.isDue(
            at: snoozed,
            anchor: stop + 600,
            snoozedUntil: snoozed,
            calendar: calendar
        ))
        // Off: never.
        #expect(ReminderSchedule().nextFire(after: stop, snoozedUntil: nil, calendar: calendar) == nil)
    }

    @Test("MB-14 the warning needs an enabled tracker, a last tick 2 min old, and 2 min of presence; a fresh tick clears it")
    func trackerWarning() throws {
        let now = try date("2024-03-14T10:00")
        func state(tick: Date) -> TrackerState {
            TrackerState(
                device: "mac",
                openBlock: nil,
                primary: nil,
                presence: TrackerPresence(state: .active, since: tick),
                health: TrackerHealth(lastTick: tick, version: "1.0 (1)", sources: [])
            )
        }
        let stale = state(tick: now - 180)
        #expect(TrackerWarning.isActive(registration: .enabled, state: stale, presentSince: now - 600, now: now))
        #expect(TrackerWarning.isActive(registration: .enabled, state: nil, presentSince: now - 600, now: now))
        #expect(!TrackerWarning.isActive(registration: .enabled, state: stale, presentSince: now - 60, now: now))
        #expect(!TrackerWarning.isActive(registration: .notRegistered, state: stale, presentSince: now - 600, now: now))
        #expect(!TrackerWarning.isActive(registration: .enabled, state: state(tick: now - 5), presentSince: now - 600, now: now))
    }

    @Test("TRK-31 the pane's status follows the liveness rule: running, delayed at 90 s, not running at 2 min, off when unregistered")
    func liveness() throws {
        let now = try date("2024-03-14T10:00")
        func state(age: TimeInterval) -> TrackerState {
            TrackerState(
                device: "mac",
                openBlock: nil,
                primary: nil,
                presence: TrackerPresence(state: .active, since: now),
                health: TrackerHealth(lastTick: now - age, version: "1.0 (1)", sources: [])
            )
        }
        #expect(TrackerLiveness(registration: .enabled, state: state(age: 12), now: now)
            .statusLine(now: now) == "Tracker running · last tick 12 s ago")
        #expect(TrackerLiveness(registration: .enabled, state: state(age: 90), now: now)
            .statusLine(now: now) == "Tracker delayed · last tick 1 min ago")
        #expect(TrackerLiveness(registration: .enabled, state: state(age: 120), now: now) == .notRunning(lastTick: now - 120))
        #expect(TrackerLiveness(registration: .enabled, state: nil, now: now) == .notRunning(lastTick: nil))
        #expect(TrackerLiveness(registration: .notRegistered, state: state(age: 1), now: now) == .off)
    }
}
