// Sample: one observation of one device at one moment
// (activity_tracking.md §2.2, §2.7).

public import Foundation

/// One observation: a time, a device, where it came from, a presence state,
/// the foreground Item, and the background Items.
public struct Sample: Sendable, Hashable {
    /// Whole seconds; the logs have no finer resolution.
    public var time: Date
    /// The Mac's hardware UUID, an iOS device's `deviceID`, or `remote`.
    public var deviceID: String
    public var source: SampleSource
    public var state: TrackerPresenceState
    /// What attention is on; `nil` unless the state is `active` or `passive`.
    public var foreground: ActivityItem?
    public var background: [ActivityItem]

    public init(
        time: Date,
        deviceID: String,
        source: SampleSource,
        state: TrackerPresenceState,
        foreground: ActivityItem? = nil,
        background: [ActivityItem] = []
    ) {
        self.time = Date(timeIntervalSince1970: time.timeIntervalSince1970.rounded(.down))
        self.deviceID = deviceID
        self.source = source
        self.state = state
        self.foreground = state.isAttentive ? foreground : nil
        self.background = background
    }

    /// Whether the Sample is attention: `active` or `passive` with a foreground Item.
    public var isAttentive: Bool {
        state.isAttentive && foreground != nil
    }

    /// The series this Sample continues: its device and source, and for
    /// Screen Time its set, for automations its app, which report in
    /// parallel. A Sample covers the time up to the next of its series.
    public var series: String {
        let series = source == .screenTime || source == .intent ? foreground?.app ?? "" : ""
        return "\(deviceID)\u{1F}\(source.rawValue)\u{1F}\(series)"
    }

    /// The competition's rank of the Sample's foreground (§2.7 step 2), 0 the highest.
    public var rank: Int {
        switch source {
        case .live, .appUsage: 0
        case .app: 1
        case .intent: 2
        case .webext: 3
        case .screenTime: foreground?.appID == ActivityItem.everythingAppID ? 5 : 4
        case .safariHistory: 6
        // A Focus's Samples are `paused`, never attentive, so they never compete.
        case .focus: 7
        }
    }

    /// The Sample with its Items passed through `transform` (exclusions,
    /// redaction); a foreground the transform drops leaves the time a gap.
    public func mapItems(_ transform: (ActivityItem) -> ActivityItem?) -> Self {
        var result = self
        result.foreground = foreground.flatMap(transform)
        result.background = background.compactMap(transform)
        return result
    }
}

/// Where a Sample came from (§2.2).
public enum SampleSource: String, Sendable, Hashable, CaseIterable {
    /// A pass of the local activity loop.
    case live
    /// Rebuilt from macOS app usage for time the agent didn't run.
    case appUsage
    /// A visit Safari synced from another device.
    case safariHistory
    case screenTime
    /// A Safari tab of the iOS web extension.
    case webext
    /// A Shortcuts automation.
    case intent
    /// TimeTracking's own time on an iPhone or iPad.
    case app
    /// A Focus that pauses collection.
    case focus

    /// The sources of the Mac.
    public static let mac: Set<Self> = [.live, .appUsage]
    /// The sources the iOS app reports, which the remote loop replaces per device-date.
    public static let iOS: Set<Self> = [.screenTime, .webext, .intent, .app, .focus]
}
