// PresenceTracker: the presence verdict of each tick and event
// (activity_tracking.md §2.4 step 1, §2.5, §3.4, §4.4).

import Foundation
import TimeTrackingCore

/// What the system reports about input and display state.
nonisolated struct PresenceReading: Hashable, Sendable {
    /// Seconds since the last keyboard, mouse, or trackpad input.
    var idleSeconds: TimeInterval
    var displayAsleep: Bool
    var locked: Bool
    /// Whether another user owns the console (fast user switching).
    var otherUserOnConsole: Bool

    init(idleSeconds: TimeInterval = 0, displayAsleep: Bool = false, locked: Bool = false, otherUserOnConsole: Bool = false) {
        self.idleSeconds = idleSeconds
        self.displayAsleep = displayAsleep
        self.locked = locked
        self.otherUserOnConsole = otherUserOnConsole
    }
}

/// The presence state machine.
///
/// A sample is `idle` when the input has been idle longer than `idle_after`
/// and no passive item is frontmost, or when the display is off, the screen
/// is locked, or another user owns the console (`locked` and `other_user`
/// are reported as such). Passive apps, passive domains, and meeting and
/// screen-sharing apps keep the state `passive` while frontmost, up to
/// `passive_limit` without input; audio-only apps never do. `since` is the
/// time of the event or input that set the state.
nonisolated struct PresenceTracker: Hashable, Sendable {
    /// Meeting and screen-sharing apps, always passive while frontmost.
    static let meetingApps: Set = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime",
        "com.apple.ScreenSharing", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager",
        "com.apple.screensharing.agent", "com.logmein.GoToMeeting",
    ]
    /// Audio-only apps, never passive even when listed.
    static let audioOnlyApps: Set = [
        "com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.iTunes",
        "com.apple.Audible", "fm.overcast.overcast", "com.tidal.desktop", "com.deezer.deezer-desktop",
    ]

    private(set) var state: TrackerPresenceState = .idle
    private(set) var since: Date
    private(set) var lastInput: Date?
    private var eventLocked = false
    private var eventAsleep = false
    private var eventDisplayAsleep = false
    private var eventOtherUser = false
    private var started = false

    init(start: Date) {
        self.since = start
    }

    /// Whether an item with `bundleID` (and, for a browser tab, `domain`)
    /// counts as passive attention under `settings`.
    static func isPassive(bundleID: String, domain: String?, settings: TrackerPresenceSettings) -> Bool {
        let folded = bundleID.lowercased()
        guard !audioOnlyApps.contains(where: { $0.lowercased() == folded }) else {
            return false
        }
        if meetingApps.contains(where: { $0.lowercased() == folded }) || settings.passiveApps
            .contains(where: { $0.lowercased() == folded })
        {
            return true
        }
        if let domain {
            return BrowserItemRules.matchesDomain(domain, settings.passiveDomains)
        }
        return false
    }

    /// Applies a presence event at `time`; returns whether the state changed.
    @discardableResult
    mutating func apply(_ event: PresenceEvent, at time: Date) -> Bool {
        switch event {
        case .lock:
            eventLocked = true
        case .unlock:
            eventLocked = false
        case .sleep:
            eventAsleep = true
        case .wake:
            eventAsleep = false
        case .displaySleep:
            eventDisplayAsleep = true
        case .displayWake:
            eventDisplayAsleep = false
        case .userSwitch:
            eventOtherUser = true
        case .userReturn:
            eventOtherUser = false
        }
        if let newState = event.state, newState != state {
            state = newState
            since = time
            started = true
            return true
        }
        return false
    }

    /// Whether the reading and the events rule out attention before any
    /// focus is resolved (asleep, other user, locked, display off).
    func blockedState(_ reading: PresenceReading) -> TrackerPresenceState? {
        if eventAsleep {
            return .asleep
        }
        if eventOtherUser || reading.otherUserOnConsole {
            return .otherUser
        }
        if eventLocked || reading.locked {
            return .locked
        }
        if eventDisplayAsleep || reading.displayAsleep {
            return .idle
        }
        return nil
    }

    /// The verdict of a tick at `now`. `passiveCandidate` says whether the
    /// frontmost item is passive (see `isPassive`).
    mutating func update(
        reading: PresenceReading,
        now: Date,
        passiveCandidate: Bool,
        settings: TrackerPresenceSettings
    ) -> TrackerPresenceState {
        let input = now.addingTimeInterval(-max(0, reading.idleSeconds))
        lastInput = input
        let verdict: TrackerPresenceState
        let blocked = blockedState(reading)
        if let blocked {
            verdict = blocked
        } else if reading.idleSeconds > settings.idleAfter {
            verdict = passiveCandidate && reading.idleSeconds <= settings.passiveLimit ? .passive : .idle
        } else {
            verdict = .active
        }
        if verdict != state || !started {
            // The input that set an input-driven state is the last one; an
            // event-driven state noticed by a tick starts at the tick.
            since = blocked == nil ? input : now
            state = verdict
            started = true
        }
        return verdict
    }
}
