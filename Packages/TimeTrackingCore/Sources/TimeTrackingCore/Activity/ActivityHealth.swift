// ActivityHealth: the Activity section's health footer, the empty states,
// and the exclusion drafts (spec_planner_activity.md §1.9, §1.10, §4, §5).

public import Foundation

/// The footer's status dot.
public enum ActivityHealthDot: Sendable, Hashable {
    case green
    case yellow
    case red
    case gray
}

/// The health footer.
public struct ActivityHealth: Sendable, Hashable {
    public var dot: ActivityHealthDot
    /// "Tracker running · last tick 12 s ago" or "Mac tracker: last tick 2 min ago".
    public var statusLine: String
    /// "Terminal, Browsers, Files".
    public var activeSources: [String]
    /// "Knowledge store off (Full Disk Access not granted)", in the warning color.
    public var problems: [String]
    /// Agent version, every source's status, the primary item, and the presence state.
    public var tooltip: [String]

    /// The Mac footer: the Tracker pane's dot and line by the liveness rule.
    public init(registration: AgentRegistration, state: TrackerState?, now: Date) {
        let liveness = TrackerLiveness(registration: registration, state: state, now: now)
        self.dot = switch liveness {
        case .off: .gray
        case .running: .green
        case .delayed: .yellow
        case .notRunning: .red
        }
        self.statusLine = liveness.statusLine(now: now)
        let sources = state?.health.sources ?? []
        self.activeSources = sources.filter { $0.status == .active }.map(\.name)
        self.problems = sources.filter { $0.status != .active }.map { source in
            let status = source.status == .off ? "off" : "on fallback"
            return source.reason.isEmpty ? "\(source.name) \(status)" : "\(source.name) \(status) (\(source.reason))"
        }
        var tooltip: [String] = []
        if let state {
            tooltip.append("Agent \(state.health.version)")
            tooltip += sources.map { "\($0.name): \($0.status.rawValue)\($0.reason.isEmpty ? "" : " (\($0.reason))")" }
            if let primary = state.primary {
                tooltip.append([primary.context, primary.subject, primary.detail].filter { !$0.isEmpty }.joined(separator: " "))
            }
            tooltip.append("Presence: \(state.presence.state.rawValue)")
        }
        self.tooltip = tooltip
    }

    /// The iPad footer from a Mac's `LiveState` activity (§5): no sources.
    public init(remote activity: LiveState.MacActivity, now: Date) {
        let tick = activity.lastTick.map { TrackerLiveness.age(now.timeIntervalSince($0)) }
        if activity.agentRunning {
            self.dot = .green
            self.statusLine = "Mac tracker: last tick \(tick ?? "unknown") ago"
        } else {
            self.dot = .gray
            self.statusLine = "Mac tracker: last seen \(tick.map { "\($0) ago" } ?? "never")"
        }
        self.activeSources = []
        self.problems = activity.health.map { "\($0) not active" }
        var tooltip: [String] = []
        if let presence = activity.presence {
            let since = activity.since.map { " since \(TrackerLiveness.age(now.timeIntervalSince($0))) ago" } ?? ""
            tooltip.append("Presence: \(presence)\(since)")
        }
        self.tooltip = tooltip
    }

    /// Whether the footer is red (the empty state adds "The tracker was not running.").
    public var isRed: Bool {
        dot == .red
    }
}

/// What replaces the panels (§1.9).
public enum ActivityEmptyState: Sendable, Hashable {
    /// The panels show.
    case panels
    /// "Set up the tracker to see where your time goes. …"
    case setup
    /// "No activity recorded between Oct 20 and Oct 26", plus the tracker
    /// line when the footer is red.
    case noActivity(trackerNotRunning: Bool)
    /// "Nothing recorded for the selected contexts".
    case nothingForContexts

    /// The state for a summary; `everSawBlock` is the device's memory that a
    /// block existed, `trackerSetUp` whether the tracker is enabled with a
    /// `current.json` and Accessibility.
    public static func resolve(summary: ActivitySummary, everSawBlock: Bool, trackerSetUp: Bool, footerRed: Bool) -> Self {
        if !everSawBlock, !summary.hasBlocks, !trackerSetUp {
            return .setup
        }
        if !summary.hasBlocks {
            return .noActivity(trackerNotRunning: footerRed)
        }
        return summary.input.contexts.isEmpty || summary.hasFilteredTime ? .panels : .nothingForContexts
    }

    /// "No activity recorded between Oct 20 and Oct 26".
    public static func noActivityText(_ days: ClosedRange<TrackingDay>) -> String {
        let first = "\(DayText.shortMonth(days.lowerBound)) \(days.lowerBound.day)"
        let last = "\(DayText.shortMonth(days.upperBound)) \(days.upperBound.day)"
        return days.lowerBound == days.upperBound ? "No activity recorded on \(first)" : "No activity recorded between \(first) and \(last)"
    }
}

/// The unsaved exclusion the Tracker pane opens with (§4).
public enum TrackerExclusionDraft: Sendable, Hashable {
    /// `exclude_apps`; `nil` when the `contexts` map has no bundle identifier.
    case app(bundleIdentifier: String?)
    /// `exclude_tmux_sessions`.
    case tmuxSession(String)
    /// `exclude_domains`, the bare domain.
    case domain(String)

    /// The draft for excluding `context`; browsers are excluded per site.
    public static func forContext(_ context: String, bundleIdentifier: String?) -> Self? {
        let item = ActivityContext(context)
        guard !item.isPrivate else {
            return nil
        }
        switch item.kind {
        case .session: return .tmuxSession(String(context.dropFirst("tmux:".count)))
        case .app: return .app(bundleIdentifier: bundleIdentifier)
        case .browser: return nil
        }
    }

    /// The draft for excluding a site subject.
    public static func forSite(_ subject: String) -> Self {
        .domain(ActivityContext.domain(ofSite: subject))
    }

    /// The prefilled value.
    public var value: String {
        switch self {
        case let .app(bundleIdentifier): bundleIdentifier ?? ""
        case let .tmuxSession(name): name
        case let .domain(domain): domain
        }
    }
}
