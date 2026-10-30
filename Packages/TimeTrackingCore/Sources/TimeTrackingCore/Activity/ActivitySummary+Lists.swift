// ActivitySummary+Lists: the Contexts, Subjects, and In the background panels
// (spec_planner_activity.md §1.6, §1.7).

/// A row of the Contexts panel.
public struct ActivityContextRow: Sendable, Hashable, Identifiable {
    /// The context, or `nil` for "Not itemized".
    public var context: String?
    public var seconds: Int
    /// The share of the unfiltered total, 0 to 1.
    public var share: Double

    public var id: String {
        context ?? "(not itemized)"
    }

    public var isPrivate: Bool {
        context.map { ActivityContext($0).isPrivate } ?? false
    }
}

/// The segmented control of the Subjects panel.
public enum ActivitySubjectKind: String, Sendable, Hashable, CaseIterable {
    case all
    case sites
    case sessions
    case folders

    public var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// The kind the control switches to when the filter changes (§1.6).
    public static func automatic(for contexts: Set<String>) -> Self {
        let kinds = Set(contexts.map { ActivityContext($0).kind })
        guard kinds.count == 1, let kind = kinds.first else {
            return .all
        }
        switch kind {
        case .browser: return .sites
        case .session: return .sessions
        case .app: return .all
        }
    }
}

/// A row of the Subjects panel.
public struct ActivitySubjectRow: Sendable, Hashable, Identifiable {
    /// The subject, or `nil` for "Other (not itemized)".
    public var subject: String?
    /// Its contexts, largest first.
    public var contexts: [String]
    public var seconds: Int
    /// The blocks with time on the subject.
    public var blockIDs: [ActivityBlock.ID]
    /// How many of them have a detail record on this Mac.
    public var detailCount: Int

    public var id: String {
        subject ?? "(other)"
    }

    /// The row has a chevron into its details.
    public var hasDetails: Bool {
        detailCount > 0
    }

    /// Whether the row belongs under `kind`.
    public func matches(_ kind: ActivitySubjectKind) -> Bool {
        guard let subject else {
            return kind == .all
        }
        switch kind {
        case .all: return true
        case .sites: return contexts.contains { ActivityContext($0).kind == .browser }
        case .sessions: return contexts.contains { ActivityContext($0).kind == .session }
        case .folders: return subject.hasPrefix("/") || subject.hasPrefix("~")
        }
    }
}

/// A secondary of the In the background panel.
public struct ActivityBackgroundRow: Sendable, Hashable, Identifiable {
    public var context: String
    public var subject: String
    public var seconds: Int

    public var id: String {
        "\(context)\u{1F}\(subject)"
    }

    /// "claude refactor-parser" or "make (~/Code/app)".
    public var title: String {
        let name = ActivityContext(context).kind == .session ? ActivityContext(context).displayName() : context
        guard !subject.isEmpty else {
            return name
        }
        return subject.hasPrefix("/") || subject.hasPrefix("~") ? "\(name) (\(subject))" : "\(name) \(subject)"
    }
}

extension ActivitySummary {
    /// The Contexts panel (§1.6): the selected contexts, shares of the
    /// unfiltered total, and "Not itemized" without a filter.
    public var contextRows: [ActivityContextRow] {
        let total = Double(max(unfilteredTotal, 1))
        var rows = ranking.filter { input.contexts.isEmpty || input.contexts.contains($0.context) }
            .map { ActivityContextRow(context: $0.context, seconds: $0.seconds, share: Double($0.seconds) / total) }
        if input.contexts.isEmpty {
            let rest = notItemizedSeconds
            if rest > 0 {
                rows.append(ActivityContextRow(context: nil, seconds: rest, share: Double(rest) / total))
            }
        }
        return rows
    }

    /// `a` minus item seconds over the range.
    public var notItemizedSeconds: Int {
        blocks.reduce(0) { $0 + max(0, $1.activeSeconds - $1.items.reduce(0) { $0 + $1.seconds }) }
    }

    /// The Subjects panel's rows under the filter, largest first, plus
    /// "Other (not itemized)" without a filter.
    public var subjectRows: [ActivitySubjectRow] {
        var seconds: [String: Int] = [:]
        var contexts: [String: [String: Int]] = [:]
        var blockIDs: [String: [ActivityBlock.ID]] = [:]
        for block in blocks {
            for item in selectedItems(block) where !item.subject.isEmpty {
                seconds[item.subject, default: 0] += item.seconds
                contexts[item.subject, default: [:]][item.context, default: 0] += item.seconds
                if blockIDs[item.subject]?.last != block.id {
                    blockIDs[item.subject, default: []].append(block.id)
                }
            }
        }
        var rows = seconds.map { subject, value in
            let ids = blockIDs[subject] ?? []
            let ranked = (contexts[subject] ?? [:]).sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
            let isPrivate = ActivityContext.isPrivateSite(subject, contexts: ranked, rules: input.exclusions)
            return ActivitySubjectRow(
                subject: subject,
                contexts: ranked,
                seconds: value,
                blockIDs: ids,
                detailCount: isPrivate ? 0 : ids.filter { input.details[$0] != nil }.count
            )
        }
        .sorted { ($1.seconds, $0.id) < ($0.seconds, $1.id) }
        if input.contexts.isEmpty {
            let rest = unfilteredTotal - rows.reduce(0) { $0 + $1.seconds }
            if rest > 0 {
                rows.append(ActivitySubjectRow(subject: nil, contexts: [], seconds: rest, blockIDs: [], detailCount: 0))
            }
        }
        return rows
    }

    /// The In the background panel: secondaries by seconds, filtered by context.
    public var backgroundRows: [ActivityBackgroundRow] {
        var seconds: [ActivityBackgroundRow: Int] = [:]
        for block in blocks {
            for item in block.background where input.contexts.isEmpty || input.contexts.contains(item.context) {
                seconds[ActivityBackgroundRow(context: item.context, subject: item.subject, seconds: 0), default: 0] += item.seconds
            }
        }
        return seconds.map { key, value in
            var row = key
            row.seconds = value
            return row
        }
        .sorted { ($1.seconds, $0.id) < ($0.seconds, $1.id) }
    }

    /// The chips beyond the first eight whose display name contains `search`.
    public func moreContexts(search: String, displayName: (String) -> String = { ActivityContext($0).displayName() }) -> [ContextTotal] {
        let rest = ranking.dropFirst(8)
        let needle = search.trimmed.folded
        guard !needle.isEmpty else {
            return Array(rest)
        }
        return rest.filter { displayName($0.context).folded.contains(needle) || $0.context.folded.contains(needle) }
    }
}

extension ActivityContext {
    /// Whether a site subject lies under `private_domains` (no details).
    static func isPrivateSite(_ subject: String, contexts: [String], rules: ExclusionRules?) -> Bool {
        guard let rules, contexts.contains(where: { ActivityContext($0).kind == .browser }) else {
            return false
        }
        return rules.isPrivateDomain(domain(ofSite: subject))
    }
}
