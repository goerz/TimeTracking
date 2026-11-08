// ScreenTimeController: registering the DeviceActivity Screen Time and handling its
// callbacks, early ones included (ios.md §9.2).

import Foundation

/// The DeviceActivity center as the Screen Time uses it; the live one wraps
/// `DeviceActivityCenter`, tests record.
public protocol ScreenTimeMonitoring: Sendable {
    /// Starts (or replaces) the repeating midnight-to-midnight schedule of
    /// `set` with `registration`'s events; throws when the system refuses.
    func startMonitoring(_ registration: ScreenTimeRegistration, for set: ScreenTimeSet) throws
    /// Stops the schedules of `setIDs`.
    func stopMonitoring(_ setIDs: [String])
}

/// What the app and the monitor extension do with Screen Time.
///
/// Each set registers a window of thresholds (`ScreenTimePlan`). The day's
/// first registration uses absolute thresholds with
/// `includesPastActivity: true`; every later one (the next window, a
/// re-registration after an early callback, a configuration change) is a
/// new generation whose thresholds are the minutes remaining after the
/// last counted step, without past activity. A callback for step k counts
/// when it comes no earlier than its ledger time, the last counted step's
/// time plus the minutes between the two steps (the day's start for the
/// first step); it appends a `screenTime` line with `n = k`. An earlier
/// callback is logged with `"early": true`, not counted, and, unless its
/// registration was already replaced, the window is re-registered under a
/// new generation. Callbacks for counted steps, other days, or unknown
/// sets are ignored.
public struct ScreenTimeController: Sendable {
    public let store: any ScreenTimeStore
    public let monitor: any ScreenTimeMonitoring
    public let log: CollectionLog

    public init(store: any ScreenTimeStore, monitor: any ScreenTimeMonitoring, log: CollectionLog) {
        self.store = store
        self.monitor = monitor
        self.log = log
    }

    private var now: Date {
        log.clock.now
    }

    private var timeZone: TimeZone {
        log.timeZone
    }

    /// `YYYY-MM-DD` of `date`.
    private func dayKey(_ date: Date) -> String {
        ActivityTimestamp.day(date, timeZone: timeZone)
    }

    private func budget(for set: ScreenTimeSet) -> Int {
        ScreenTimePlan.budgets(cap: store.eventCap ?? ScreenTimePlan.defaultCap, sets: store.screenTimeSets)[set.id] ?? 1
    }

    // MARK: Registration

    /// The events to register for `set` in `state`.
    public func registration(for set: ScreenTimeSet, state: ScreenTimeSetState) -> ScreenTimeRegistration {
        let day = state.day.replacingOccurrences(of: "-", with: "")
        let base = state.countedStep ?? 0
        let events = state.pendingSteps.map { step in
            ScreenTimeEventSpec(
                name: ScreenTimeEventName(setID: set.id, day: day, generation: state.generation, step: step).text,
                minutes: state.generation == 0 ? step : step - base,
                includesPastActivity: state.generation == 0
            )
        }
        return ScreenTimeRegistration(setID: set.id, events: events)
    }

    /// The app: registers every set (after enabling, a set change, or at
    /// launch) and stops `removed`. Sets with a ledger of today keep it and
    /// register the rest of a fresh window as a new generation.
    public func configure(removed: [String] = []) throws {
        if !removed.isEmpty {
            monitor.stopMonitoring(removed)
            for id in removed {
                store.setScreenTimeState(nil, for: id)
            }
        }
        let today = dayKey(now)
        for set in store.screenTimeSets {
            // The monitor extension may count a step meanwhile; each set's
            // ledger is read and written under the App Group lock.
            try store.withExclusiveAccess {
                var state: ScreenTimeSetState
                if let existing = store.screenTimeState(for: set.id), existing.day == today {
                    state = existing
                    state.generation += 1
                    state.window = ScreenTimePlan.window(
                        after: existing.countedStep,
                        budget: budget(for: set),
                        everything: set.isEverything
                    )
                } else {
                    state = fresh(set, day: today)
                }
                try monitor.startMonitoring(registration(for: set, state: state), for: set)
                store.setScreenTimeState(state, for: set.id)
            }
        }
    }

    /// Stops every set (the master switch turned off, or authorization lost).
    public func stopAll() {
        monitor.stopMonitoring(store.screenTimeSets.map(\.id))
    }

    /// The monitor extension's `intervalDidStart`: a new day starts fresh.
    public func intervalDidStart(setID: String) throws {
        guard let set = store.screenTimeSets.first(where: { $0.id == setID }) else {
            return
        }
        try store.withExclusiveAccess {
            let state = fresh(set, day: dayKey(now))
            try monitor.startMonitoring(registration(for: set, state: state), for: set)
            store.setScreenTimeState(state, for: set.id)
        }
    }

    private func fresh(_ set: ScreenTimeSet, day: String) -> ScreenTimeSetState {
        ScreenTimeSetState(day: day, window: ScreenTimePlan.window(after: nil, budget: budget(for: set), everything: set.isEverything))
    }

    // MARK: Callbacks

    /// What a callback did.
    public enum Outcome: Sendable, Hashable {
        case counted(step: Int)
        case early(step: Int, reregistered: Bool)
        case ignored
    }

    /// The monitor extension's `eventDidReachThreshold`.
    @discardableResult
    public func thresholdReached(_ eventName: String) throws -> Outcome {
        guard let name = ScreenTimeEventName(eventName), let set = store.screenTimeSets.first(where: { $0.id == name.setID }) else {
            return .ignored
        }
        let now = now
        let today = dayKey(now)
        guard name.day == today.replacingOccurrences(of: "-", with: "") else {
            return .ignored
        }
        // The app may reconfigure the set meanwhile; the ledger is read and
        // written under the App Group lock.
        return try store.withExclusiveAccess { () throws -> Outcome in
            var state = store.screenTimeState(for: set.id).flatMap { $0.day == today ? $0 : nil } ?? fresh(set, day: today)
            let base = state.countedStep ?? 0
            guard name.step > base else {
                return .ignored
            }
            let since = state.countedAt ?? ActivityTimestamp.startOfDay(now, timeZone: timeZone)
            let earliest = since.addingTimeInterval(TimeInterval(name.step - base) * 60)
            if now < earliest {
                return try early(name, set: set, state: state)
            }
            try log.append(.screenTime, label: set.label, kind: "minute", payload: DeviceEvent.payloadText(["n": name.step]))
            state.countedStep = name.step
            state.countedAt = now
            if name.step >= (state.window.last ?? 0) {
                state.generation += 1
                state.window = ScreenTimePlan.window(after: name.step, budget: budget(for: set), everything: set.isEverything)
                if !state.window.isEmpty {
                    try monitor.startMonitoring(registration(for: set, state: state), for: set)
                }
            }
            store.setScreenTimeState(state, for: set.id)
            return .counted(step: name.step)
        }
    }

    /// Logs a threshold reached before its minutes could have passed and,
    /// when it belongs to the current registration, registers the set again.
    private func early(_ name: ScreenTimeEventName, set: ScreenTimeSet, state: ScreenTimeSetState) throws -> Outcome {
        try log.append(.screenTime, label: set.label, kind: "minute", payload: DeviceEvent.payloadText(["n": name.step, "early": true]))
        guard name.generation == state.generation else {
            return .early(step: name.step, reregistered: false)
        }
        var state = state
        state.generation += 1
        try monitor.startMonitoring(registration(for: set, state: state), for: set)
        store.setScreenTimeState(state, for: set.id)
        return .early(step: name.step, reregistered: true)
    }
}
