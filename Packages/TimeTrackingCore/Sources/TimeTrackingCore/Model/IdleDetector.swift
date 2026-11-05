// IdleDetector: the Timer's idle detection (timer.md §6).

public import Foundation

/// What happens on a lock or sleep (§6.2).
public enum IdleLockBehavior: String, Codable, Sendable, CaseIterable {
    /// "Ask when I return".
    case ask
    /// "Stop the entry at that moment".
    case stop
    /// "Keep tracking".
    case keep
}

/// The device settings of §6.2.
public struct IdleSettings: Hashable, Sendable {
    public var detectIdle: Bool
    public var thresholdMinutes: Int
    public var onLockOrSleep: IdleLockBehavior
    public var stopOnShutdown: Bool

    public init(detectIdle: Bool = true, thresholdMinutes: Int = 10, onLockOrSleep: IdleLockBehavior = .ask, stopOnShutdown: Bool = true) {
        self.detectIdle = detectIdle
        self.thresholdMinutes = thresholdMinutes
        self.onLockOrSleep = onLockOrSleep
        self.stopOnShutdown = stopOnShutdown
    }

    public var threshold: TimeInterval {
        TimeInterval(min(max(thresholdMinutes, 1), 120) * 60)
    }
}

/// A system event the app records (§6.1).
public enum IdleSystemEvent: Hashable, Sendable {
    case lock
    case unlock
    case sleep
    case wake
    /// Fast user switch away from this session.
    case sessionResigned
    case sessionActivated
    case shutdown
}

/// The detector's verdict.
public enum IdleDecision: Hashable, Sendable {
    /// Show "You have been away" for an absence starting at `idleStart`.
    case prompt(idleStart: Date)
    /// Stop the running entry at `at` without a prompt.
    case stop(at: Date)
}

/// Turns input-idle samples, system events, and the tracker's presence into
/// prompts. The owner samples every 10 s and passes each event as it comes.
public struct IdleDetector: Hashable, Sendable {
    public var settings: IdleSettings
    /// The start of the current absence, if one is long enough or began with
    /// a lock or sleep.
    public private(set) var absenceStart: Date?
    /// Whether the current absence contains a lock, sleep, or user switch.
    public private(set) var absenceHasLock = false
    /// Whether the session is locked, asleep, or switched away.
    public private(set) var isAway = false

    public init(settings: IdleSettings = IdleSettings()) {
        self.settings = settings
    }

    /// One sample: `idleSeconds` since the last input event at `now`.
    /// `presence` is the tracker's state when the tracker runs.
    public mutating func sample(
        idleSeconds: TimeInterval,
        at now: Date,
        isRunning: Bool,
        presence: TrackerPresence? = nil
    ) -> IdleDecision? {
        guard isRunning else {
            reset()
            return nil
        }
        if let presence, !applyPresence(presence) {
            return nil
        }
        if isAway {
            return nil
        }
        let inputStopped = now - idleSeconds
        if idleSeconds >= settings.threshold, settings.detectIdle {
            absenceStart = min(absenceStart ?? inputStopped, inputStopped)
            return nil
        }
        // Input resumed (or never stopped long enough).
        guard let start = absenceStart else {
            return nil
        }
        let lasted = inputStopped.timeIntervalSince(start)
        let hadLock = absenceHasLock
        reset()
        if hadLock {
            switch settings.onLockOrSleep {
            case .ask:
                return .prompt(idleStart: start)
            case .keep, .stop:
                return nil
            }
        }
        guard settings.detectIdle, lasted >= settings.threshold else {
            return nil
        }
        return .prompt(idleStart: start)
    }

    /// A system event at `at`.
    public mutating func event(_ event: IdleSystemEvent, at: Date, isRunning: Bool) -> IdleDecision? {
        switch event {
        case .lock, .sleep, .sessionResigned:
            isAway = true
            guard isRunning else {
                return nil
            }
            switch settings.onLockOrSleep {
            case .stop:
                reset()
                isAway = true
                return .stop(at: at)
            case .keep:
                return nil
            case .ask:
                noteLock(at: at)
                return nil
            }
        case .unlock, .wake, .sessionActivated:
            isAway = false
            return nil
        case .shutdown:
            guard isRunning, settings.stopOnShutdown else {
                return nil
            }
            return .stop(at: at)
        }
    }

    /// Forgets the current absence (after a prompt resolves or a stop).
    public mutating func reset() {
        absenceStart = nil
        absenceHasLock = false
    }

    /// Applies the tracker's presence; `false` when the sample ends there.
    private mutating func applyPresence(_ presence: TrackerPresence) -> Bool {
        switch presence.state {
        case .passive:
            // Passive attention (a video, a call) is not an absence.
            reset()
            return false
        case .locked, .asleep, .otherUser:
            // Still away: the prompt waits for the return.
            noteLock(at: presence.since)
            return false
        case .active, .idle:
            return true
        }
    }

    private mutating func noteLock(at time: Date) {
        guard settings.onLockOrSleep == .ask else {
            return
        }
        absenceStart = min(absenceStart ?? time, time)
        absenceHasLock = true
    }
}
