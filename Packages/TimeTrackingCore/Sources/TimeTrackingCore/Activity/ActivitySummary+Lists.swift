// ActivitySummary+Lists: the Contexts, Subjects, and In the background panels
// (activity.md §1.6, §1.7).

/// A row of the Contexts panel.
public struct ActivityContextRow: Sendable, Hashable, Identifiable {
    /// The context, or `nil` for "Brief activity".
    public var context: String?
    public var seconds: Int
    /// The share of the unfiltered total, 0 to 1.
    public var share: Double

    public var id: String {
        context ?? "(brief activity)"
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
        switch self {
        case .all: "All"
        case .sites: "Sites"
        case .sessions: "Sessions"
        case .folders: "Folders"
        }
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
    /// The subject, or `nil` for "Other (brief activity)".
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

extension ActivityBackgroundStretch {
    /// "In the background while away: Claude refactor-parser 38m", the
    /// Calendar's text for the stretch.
    public var summaryText: String {
        let names = items.map { item in
            "\(ActivityBackgroundRow.title(context: item.context, subject: item.subject)) \(ActivityText.duration(item.seconds))"
        }
        return "In the background while away: " + names.joined(separator: ", ")
    }
}

/// A background item of the In the background panel.
public struct ActivityBackgroundRow: Sendable, Hashable, Identifiable {
    public var context: String
    public var subject: String
    public var seconds: Int
    /// The part of `seconds` in background stretches, while the user was away.
    public var awaySeconds = 0

    public var id: String {
        "\(context)\u{1F}\(subject)"
    }

    /// "Claude refactor-parser" or "paper (tmux) in ~/Code/app".
    public var title: String {
        Self.title(context: context, subject: subject)
    }

    /// The name of a background item: its context as Activity names it,
    /// then its subject, a folder after "in".
    public static func title(context: String, subject: String) -> String {
        let name = ActivityContext(context).label()
        guard !subject.isEmpty else {
            return name
        }
        return subject.hasPrefix("/") || subject.hasPrefix("~") ? "\(name) in \(subject)" : "\(name) \(subject)"
    }
}

extension ActivitySummary {
    /// The Contexts panel (§1.6): the selected contexts, shares of the
    /// unfiltered total, and "Brief activity" without a filter.
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
    /// "Other (brief activity)" without a filter.
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

    /// The In the background panel: the background items of the blocks and
    /// of the background stretches by seconds, filtered by context.
    public var backgroundRows: [ActivityBackgroundRow] {
        var rows: [String: ActivityBackgroundRow] = [:]
        func add(_ item: ActivityItem, away: Bool) {
            guard input.contexts.isEmpty || input.contexts.contains(item.context) else {
                return
            }
            var row = ActivityBackgroundRow(context: item.context, subject: item.subject, seconds: 0)
            row = rows[row.id] ?? row
            row.seconds += item.seconds
            row.awaySeconds += away ? item.seconds : 0
            rows[row.id] = row
        }
        for block in blocks {
            block.background.forEach { add($0, away: false) }
        }
        for stretch in stretches {
            stretch.items.forEach { add($0, away: true) }
        }
        return rows.values.sorted { ($1.seconds, $0.id) < ($0.seconds, $1.id) }
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
