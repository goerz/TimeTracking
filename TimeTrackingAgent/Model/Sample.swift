// Sample: one tick's or event's observation (activity_tracking.md §2.1,
// §2.4, §4.1).

import Foundation
import TimeTrackingCore

/// A sample: time, presence state, the primary item, secondaries, and debug
/// fields. Exclusions are already applied.
nonisolated struct Sample: Hashable, Sendable {
    /// Whole seconds; the logs have no finer resolution.
    var time: Date
    var state: TrackerPresenceState
    /// The presence event this sample records, if any.
    var event: PresenceEvent?
    /// `nil` unless the state is `active` or `passive`.
    var primary: SampleItem?
    var secondaries: [SampleItem]
    /// Debug: the frontmost app's bundle identifier.
    var bundleID: String
    /// Debug: the window title after `exclude_title_keywords`.
    var title: String
    /// Debug: the tmux target `session:window.pane`.
    var tmuxTarget: String
    /// The sampled URL as the detail log may keep it (empty for none).
    var url: String

    init(
        time: Date,
        state: TrackerPresenceState,
        event: PresenceEvent? = nil,
        primary: SampleItem? = nil,
        secondaries: [SampleItem] = [],
        bundleID: String = "",
        title: String = "",
        tmuxTarget: String = "",
        url: String = ""
    ) {
        self.time = Date(timeIntervalSince1970: time.timeIntervalSince1970.rounded(.down))
        self.state = state
        self.event = event
        self.primary = primary
        self.secondaries = secondaries
        self.bundleID = bundleID
        self.title = title
        self.tmuxTarget = tmuxTarget
        self.url = url
    }

    /// Whether the sample counts as attention (`active` or `passive`).
    var isAttentive: Bool {
        (state == .active || state == .passive) && primary != nil
    }
}

/// The presence events that refine timing between ticks (§3.4).
nonisolated enum PresenceEvent: String, Hashable, Sendable, CaseIterable {
    case lock
    case unlock
    case sleep
    case wake
    case displaySleep = "display_sleep"
    case displayWake = "display_wake"
    case userSwitch = "user_switch"
    case userReturn = "user_return"

    /// Whether the event closes the open block at its time (§2.6).
    var closesBlock: Bool {
        switch self {
        case .lock, .sleep, .displaySleep, .userSwitch:
            true
        case .unlock, .wake, .displayWake, .userReturn:
            false
        }
    }

    /// The presence state the event sets, if it sets one.
    var state: TrackerPresenceState? {
        switch self {
        case .lock:
            .locked
        case .sleep:
            .asleep
        case .displaySleep:
            .idle
        case .userSwitch:
            .otherUser
        case .unlock, .wake, .displayWake, .userReturn:
            nil
        }
    }
}
