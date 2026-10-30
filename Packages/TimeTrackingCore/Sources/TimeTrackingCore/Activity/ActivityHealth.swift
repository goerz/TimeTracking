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

/// The health footer. It lists only the sources with a problem; the
/// Tracker pane lists every source.
public struct ActivityHealth: Sendable, Hashable {
    public var dot: ActivityHealthDot
    /// "Tracker running · checked 12 s ago" or "Mac tracker: checked 2 min ago".
    public var statusLine: String
    /// Always empty: the footer no longer lists working sources. Kept only
    /// until no view reads it; remove it then.
    public var activeSources: [String] = []
    /// "Browser history: Full Disk Access is off; Safari pages are recorded
    /// by site only", in the warning color: only sources that are limited or off.
    public var problems: [String]
    /// The tracker version, the primary item ("Now: paper (tmux) · draft"),
    /// and the presence ("In use").
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
        self.problems = sources.filter { $0.status != .active }.map { source in
            "\(source.displayName): \(source.reason.isEmpty ? source.status.displayName : source.reason)"
        }
        var tooltip: [String] = []
        if let state {
            tooltip.append("Tracker version \(state.health.version)")
            if let primary = state.primary, !primary.text.isEmpty {
                tooltip.append("Now: \(primary.text)")
            }
            tooltip.append(state.presence.state.displayName)
        }
        self.tooltip = tooltip
    }

    /// The iPad footer from a Mac's `LiveState` activity (§5): no sources,
    /// only the ids of those with a problem.
    public init(remote activity: LiveState.MacActivity, now: Date) {
        let tick = activity.lastTick.map { TrackerLiveness.age(now.timeIntervalSince($0)) }
        if activity.agentRunning {
            self.dot = .green
            self.statusLine = tick.map { "Mac tracker: checked \($0) ago" } ?? "Mac tracker: running"
        } else {
            self.dot = .gray
            self.statusLine = tick.map { "Mac tracker: last checked \($0) ago" } ?? "Mac tracker: not checked yet"
        }
        self.problems = activity.health.map { "\(TrackerSourceHealth.name(forID: $0) ?? $0) needs attention on the Mac" }
        var tooltip: [String] = []
        if let presence = activity.presence {
            let word = TrackerPresenceState(rawValue: presence)?.displayName ?? presence
            let age = activity.since.map { " for \(TrackerLiveness.age(now.timeIntervalSince($0)))" } ?? ""
            tooltip.append(word + age)
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
