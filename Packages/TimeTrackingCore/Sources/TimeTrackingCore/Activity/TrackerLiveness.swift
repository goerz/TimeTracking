// TrackerLiveness: the tracker's status by the liveness rule, as the Tracker
// pane and the menu bar warning show it (spec_activity_tracking.md §4.4, §7.4;
// spec_menubar.md §3).

public import Foundation

/// The registration status of the agent's login item, as `SMAppService`
/// reports it.
public enum AgentRegistration: String, Sendable, Hashable, CaseIterable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// The tracker's status by the rule of §4.4.
public enum TrackerLiveness: Hashable, Sendable {
    /// The agent is not registered (gray, "Tracker off").
    case off
    /// The last tick is younger than 90 seconds (green).
    case running(lastTick: Date)
    /// Running, but the last tick is 90 seconds old or older (yellow).
    case delayed(lastTick: Date)
    /// The last tick is 2 minutes old or older, or there is no `current.json` (red).
    case notRunning(lastTick: Date?)

    public init(registration: AgentRegistration, state: TrackerState?, now: Date) {
        if registration == .notRegistered || registration == .notFound {
            self = .off
            return
        }
        guard let state, state.isRunning(at: now) else {
            self = .notRunning(lastTick: state?.health.lastTick)
            return
        }
        self = state.isDelayed(at: now) ? .delayed(lastTick: state.health.lastTick) : .running(lastTick: state.health.lastTick)
    }

    /// The Tracker pane's status line ("Tracker running · checked 12 s ago").
    public func statusLine(now: Date) -> String {
        switch self {
        case .off:
            "Tracker off"
        case let .running(tick):
            "Tracker running · checked \(Self.age(now.timeIntervalSince(tick))) ago"
        case let .delayed(tick):
            "Tracker delayed · last checked \(Self.age(now.timeIntervalSince(tick))) ago"
        case .notRunning:
            "Tracker not running"
        }
    }

    /// "12 s", "1 min", "5 min", "2 h".
    static func age(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 {
            return "\(seconds) s"
        }
        if seconds < 3600 {
            return "\(seconds / 60) min"
        }
        return "\(seconds / 3600) h"
    }
}

/// The menu bar's tracker warning (`spec_menubar.md` §3).
public enum TrackerWarning {
    /// How long the Mac must have been awake, unlocked, and in the session.
    public static let presenceRequired: TimeInterval = 120

    /// Whether the warning is active: the login item is enabled, the
    /// tracker is not running, and the Mac has been present since
    /// `presentSince` for at least 2 minutes.
    public static func isActive(registration: AgentRegistration, state: TrackerState?, presentSince: Date?, now: Date) -> Bool {
        guard registration == .enabled, let presentSince, now.timeIntervalSince(presentSince) >= presenceRequired else {
            return false
        }
        return !(state?.isRunning(at: now) ?? false)
    }
}
