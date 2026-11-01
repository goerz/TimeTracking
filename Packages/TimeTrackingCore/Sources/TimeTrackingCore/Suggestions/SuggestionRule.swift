// SuggestionRule: explicit mappings in front of the model, and the
// Calendar's synced settings (spec_calendar.md §5.3, §7).

public import Foundation

/// A rule mapping a group key, context, subject prefix, or calendar-title
/// keyword to a project (and optional task), or to Ignore.
public struct SuggestionRule: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case groupKey = "group_key"
        case context
        case subjectPrefix = "subject_prefix"
        case titleKeyword = "title_keyword"

        public var title: String {
            switch self {
            case .groupKey: "Session, site, or folder"
            case .context: "App"
            case .subjectPrefix: "Starts with"
            case .titleKeyword: "Event title contains"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var pattern: String
    public var projectID: ProjectID?
    public var task: String?
    /// Ignore: matching items leave the query; empty blocks leave Fill Day.
    public var ignore: Bool

    public init(id: UUID = UUID(), kind: Kind, pattern: String, projectID: ProjectID? = nil, task: String? = nil, ignore: Bool = false) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.projectID = projectID
        self.task = task
        self.ignore = ignore
    }

    /// Whether an item of a block with `groupKey` matches (title rules never do).
    public func matches(_ item: ActivityItem, groupKey: String) -> Bool {
        switch kind {
        case .groupKey: groupKey == pattern
        case .context: item.context == pattern
        case .subjectPrefix: !pattern.isEmpty && item.subject.hasPrefix(pattern)
        case .titleKeyword: false
        }
    }

    /// The pattern as the Suggestions sheet shows it: a group key or context
    /// by its display name, other patterns as written.
    public var patternText: String {
        switch kind {
        case .groupKey: ActivityContext.groupKeyName(pattern)
        case .context: ActivityContext(pattern).label()
        case .subjectPrefix, .titleKeyword: pattern
        }
    }

    /// Whether a title rule matches the title's `k:` tokens.
    public func matches(titleTokens: Set<String>) -> Bool {
        kind == .titleKeyword && titleTokens.contains("k:" + pattern.lowercased())
    }
}

extension SyncedSettingKey<[SuggestionRule]> {
    public static var suggestionRules: Self {
        Self("calendar.suggestionRules", default: [])
    }
}

extension SyncedSettingKey<Int> {
    /// 1, 5, 10, or 15.
    public static var calendarSnapMinutes: Self {
        Self("calendar.snapMinutes", default: 5)
    }

    /// 1 to 30.
    public static var fillMinMinutes: Self {
        Self("calendar.fillMinMinutes", default: 5)
    }

    /// 30 to 730.
    public static var trainDays: Self {
        Self("calendar.trainDays", default: 180)
    }
}
