// SuggestionQuery and SuggestionCandidate: what the engine is asked and
// what it answers (spec_planner_calendar.md §5, §5.4).

public import Foundation

/// A stretch of activity to suggest a project and task for.
public struct SuggestionQuery: Sendable, Hashable {
    /// The items of one block group (weighted by the overlap share).
    public struct Part: Sendable, Hashable {
        public var groupKey: String
        public var activeSeconds: Double
        public var items: [ActivityItem]

        public init(groupKey: String, activeSeconds: Double, items: [ActivityItem]) {
            self.groupKey = groupKey
            self.activeSeconds = activeSeconds
            self.items = items
        }
    }

    public var parts: [Part]
    public var interval: DateInterval
    /// The title of a covering calendar event or time block.
    public var calendarTitle: String?
    public var previousProject: ProjectID?
    public var previousKnown: Bool
    public var timeZone: TimeZone

    public init(
        parts: [Part],
        interval: DateInterval,
        calendarTitle: String? = nil,
        previousProject: ProjectID? = nil,
        previousKnown: Bool = false,
        timeZone: TimeZone
    ) {
        self.parts = parts
        self.interval = interval
        self.calendarTitle = calendarTitle
        self.previousProject = previousProject
        self.previousKnown = previousKnown
        self.timeZone = timeZone
    }

    /// The query for `interval` over the blocks overlapping it, each
    /// weighted by the share of it inside the interval.
    public init(
        blocks: [ActivityBlock],
        interval: DateInterval,
        calendarTitle: String? = nil,
        previousProject: ProjectID? = nil,
        previousKnown: Bool = false,
        timeZone: TimeZone
    ) {
        let parts = blocks.compactMap { block -> Part? in
            let (items, groups) = SuggestionFeatures.activity(of: [block], during: interval)
            guard let seconds = groups.values.first else {
                return nil
            }
            return Part(groupKey: block.groupKey, activeSeconds: seconds, items: items)
        }
        self.init(
            parts: parts,
            interval: interval,
            calendarTitle: calendarTitle,
            previousProject: previousProject,
            previousKnown: previousKnown,
            timeZone: timeZone
        )
    }

    /// The number of activity items (feedback's `queryItems`).
    public var itemCount: Int {
        parts.reduce(0) { $0 + $1.items.count }
    }

    /// The query without the items and parts ignore rules remove.
    public func applying(_ rules: [SuggestionRule]) -> Self {
        let ignores = rules.filter(\.ignore)
        guard !ignores.isEmpty else {
            return self
        }
        var copy = self
        copy.parts = parts.compactMap { part in
            if ignores.contains(where: { $0.kind == .groupKey && $0.pattern == part.groupKey }) {
                return nil
            }
            var part = part
            let kept = part.items.filter { item in !ignores.contains { $0.matches(item, groupKey: part.groupKey) } }
            let removed = part.items.reduce(0) { $0 + $1.seconds } - kept.reduce(0) { $0 + $1.seconds }
            part.items = kept
            part.activeSeconds = max(0, part.activeSeconds - Double(removed))
            return kept.isEmpty ? nil : part
        }
        return copy
    }

    /// The features the model compares.
    public var features: SuggestionFeatures {
        SuggestionFeatures(
            items: parts.flatMap(\.items),
            groupKeys: parts.reduce(into: [:]) { $0[$1.groupKey, default: 0] += $1.activeSeconds },
            title: calendarTitle,
            interval: interval,
            previousProject: previousProject,
            previousKnown: previousKnown,
            timeZone: timeZone
        )
    }
}

/// Why a candidate was proposed (§5.4).
public enum SuggestionReason: Sendable, Hashable, Codable {
    case rule
    case groupKey(String)
    case token(String)
    case context(String)
    case hour
    case weekday
    case title

    public var text: String {
        switch self {
        case .rule: "rule"
        case let .groupKey(key): key
        case let .token(token): String(token.drop { $0 != ":" }.dropFirst())
        case let .context(context): context
        case .hour: "time of day"
        case .weekday: "weekday"
        case .title: "calendar title"
        }
    }
}

/// A proposed project and task.
public struct SuggestionCandidate: Sendable, Hashable {
    public var projectID: ProjectID?
    /// `nil` for a project-only candidate.
    public var task: String?
    public var confidence: Double
    public var reasons: [SuggestionReason]

    public init(projectID: ProjectID?, task: String?, confidence: Double, reasons: [SuggestionReason]) {
        self.projectID = projectID
        self.task = task
        self.confidence = confidence
        self.reasons = reasons
    }

    /// Nothing is prefilled below this.
    public static let suggestMin = 0.35
    /// Log skips the popover above this.
    public static let suggestAuto = 0.8

    /// Prefilled into the popover or the Fill Day row.
    public var isConfident: Bool {
        confidence >= Self.suggestMin
    }

    /// Log creates the entry directly.
    public var logsDirectly: Bool {
        confidence > Self.suggestAuto && projectID != nil && !(task ?? "").isEmpty
    }

    /// The four-segment meter: 0 to 4 lit segments.
    public var meterSegments: Int {
        min(4, max(0, Int((confidence * 4).rounded(.up))))
    }
}
