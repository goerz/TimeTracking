// ActivitySummary+Lists: the Apps, Workspaces, and In the background panels
// (activity.md §1.6, §1.7).

import Foundation

/// A row of the Apps panel.
public struct ActivityAppRow: Sendable, Hashable, Identifiable {
    public var app: String
    public var kind: ActivityAppKind
    public var seconds: Int
    /// The share of the unfiltered total, 0 to 1.
    public var share: Double

    public var id: String {
        app
    }
}

/// The segmented control of the Workspaces panel.
public enum ActivityWorkspaceKind: String, Sendable, Hashable, CaseIterable {
    case all
    /// Workspaces that are paths.
    case folders
    /// Workspaces from URLs.
    case sites

    public var title: String {
        switch self {
        case .all: "All"
        case .folders: "Folders"
        case .sites: "Sites"
        }
    }

    /// The kind the control switches to when the filter changes (§1.6):
    /// Sites when every selected app is a browser, else All.
    public static func automatic(for kinds: [ActivityAppKind]) -> Self {
        !kinds.isEmpty && kinds.allSatisfy { $0 == .browser } ? .sites : .all
    }
}

/// A row of the Workspaces panel.
public struct ActivityWorkspaceRow: Sendable, Hashable, Identifiable {
    /// The workspace as stored, a full path or name.
    public var workspace: String
    /// Its last component, "(private)" for `private`.
    public var name: String
    /// Folder, site, or neither.
    public var kind: ActivityWorkspaceKind?
    /// The bare domain of its web pages; `nil` when it has none.
    public var domain: String?
    /// Its apps, the most time first.
    public var apps: [String]
    public var seconds: Int
    /// Its items from the blocks, ranked by seconds; empty for a site of
    /// `private_domains`.
    public var items: [Item]

    /// An item of the drill-down, labeled as in the block summary.
    public struct Item: Sendable, Hashable {
        public var label: String
        public var seconds: Int
    }

    public var id: String {
        workspace
    }

    /// The workspace `private`, shown in gray.
    public var isPrivate: Bool {
        workspace == ActivityItem.privateWorkspace
    }

    /// The row has a chevron into its items.
    public var hasItems: Bool {
        !items.isEmpty
    }

    /// Whether the row belongs under `kind`; neither folders nor sites show under All only.
    public func matches(_ kind: ActivityWorkspaceKind) -> Bool {
        kind == .all || self.kind == kind
    }
}

/// A background item of the In the background panel.
public struct ActivityBackgroundRow: Sendable, Hashable, Identifiable {
    /// "Claude Code refactor-parser".
    public var label: String
    /// The item's workspace by its last component.
    public var workspaceName: String
    public var seconds: Int
    /// The part of `seconds` in background blocks, while the user was away.
    public var awaySeconds = 0

    public var id: String {
        "\(label)\u{1F}\(workspaceName)"
    }

    /// "Claude Code refactor-parser in MyApp".
    public var title: String {
        workspaceName.isEmpty || workspaceName == label ? label : "\(label) in \(workspaceName)"
    }

    /// The name of a background item: its app and its command for a job,
    /// else its session ("tmux make test", "Claude Code refactor-parser").
    public static func label(_ item: ActivityItem, jobCommands: [String]) -> String {
        ActivityBlockSummary.backgroundLabel(item, jobCommands: jobCommands).replacingOccurrences(of: " · ", with: " ")
    }
}

extension ActivityBlock {
    /// "In the background while away: Claude Code refactor-parser 38m", the
    /// Calendar's text for a background block.
    public func backgroundText(jobCommands: [String]) -> String {
        let names = background.sorted { $0.seconds > $1.seconds }.map { item in
            "\(ActivityBackgroundRow.label(item.item, jobCommands: jobCommands)) \(ActivityText.duration(item.seconds))"
        }
        return "In the background while away: " + names.joined(separator: ", ")
    }
}

extension ActivitySummary {
    /// The Apps panel (§1.6): the selected apps, shares of the unfiltered total.
    public var appRows: [ActivityAppRow] {
        let total = Double(max(unfilteredTotal, 1))
        return ranking.filter { input.apps.isEmpty || input.apps.contains($0.app) }
            .map { ActivityAppRow(app: $0.app, kind: $0.kind, seconds: $0.seconds, share: Double($0.seconds) / total) }
    }

    /// The Workspaces panel's rows under the filter, largest first.
    public var workspaceRows: [ActivityWorkspaceRow] {
        var rows: [String: WorkspaceTally] = [:]
        for block in blocks {
            for item in selectedItems(block) {
                let workspace = item.item.workspace.isEmpty ? item.item.appName : item.item.workspace
                rows[workspace, default: WorkspaceTally()].add(item)
            }
        }
        return rows.map { workspace, tally in
            let hidesItems = tally.domain.map { input.exclusions?.isPrivateDomain($0) ?? false } ?? false
            return ActivityWorkspaceRow(
                workspace: workspace,
                name: ActivityItem.workspaceName(workspace),
                kind: Self.isPath(workspace) ? .folders : (tally.domain != nil ? .sites : nil),
                domain: tally.domain,
                apps: tally.apps.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key),
                seconds: tally.seconds,
                items: hidesItems ? [] : tally.items.map { ActivityWorkspaceRow.Item(label: $0.key, seconds: $0.value) }
                    .sorted { ($1.seconds, $0.label) < ($0.seconds, $1.label) }
            )
        }
        .sorted { ($1.seconds, $0.id) < ($0.seconds, $1.id) }
    }

    /// The In the background panel: the background items of the foreground
    /// blocks and of the background blocks by seconds, filtered by app.
    public var backgroundRows: [ActivityBackgroundRow] {
        let jobs = input.settings.terminal.jobCommands
        var rows: [String: ActivityBackgroundRow] = [:]
        func add(_ item: ActivityBlockItem, away: Bool) {
            guard input.apps.isEmpty || input.apps.contains(item.item.appName) else {
                return
            }
            var row = ActivityBackgroundRow(
                label: ActivityBackgroundRow.label(item.item, jobCommands: jobs),
                workspaceName: item.item.workspaceName,
                seconds: 0
            )
            row = rows[row.id] ?? row
            row.seconds += item.seconds
            row.awaySeconds += away ? item.seconds : 0
            rows[row.id] = row
        }
        for block in blocks {
            block.background.forEach { add($0, away: false) }
        }
        for block in backgroundBlocks {
            block.background.forEach { add($0, away: true) }
        }
        return rows.values.sorted { ($1.seconds, $0.id) < ($0.seconds, $1.id) }
    }

    /// The chips beyond the first eight whose name contains `search`.
    public func moreApps(search: String) -> [AppTotal] {
        let rest = ranking.dropFirst(8)
        let needle = search.trimmed.folded
        guard !needle.isEmpty else {
            return Array(rest)
        }
        return rest.filter { $0.app.folded.contains(needle) }
    }

    private static func isPath(_ workspace: String) -> Bool {
        workspace.hasPrefix("/") || workspace.hasPrefix("~")
    }
}

/// The running totals of one workspace.
private struct WorkspaceTally {
    var seconds = 0
    var apps: [String: Int] = [:]
    var items: [String: Int] = [:]
    /// The bare domain of its first web page.
    var domain: String?

    mutating func add(_ item: ActivityBlockItem) {
        seconds += item.seconds
        apps[item.item.appName, default: 0] += item.seconds
        items[item.item.label, default: 0] += item.seconds
        let location = item.item.location.lowercased()
        if domain == nil, location.hasPrefix("http://") || location.hasPrefix("https://"), let host = URL(string: location)?.host() {
            domain = ExclusionRules.bareDomain(host)
        }
    }
}
