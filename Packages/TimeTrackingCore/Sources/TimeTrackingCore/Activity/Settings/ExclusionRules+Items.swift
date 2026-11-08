// ExclusionRules+Items: the exclusions of [privacy] applied to an Item, a
// Sample, and a block (activity_tracking.md §7.2; activity.md §4).

import Foundation

extension ExclusionRules {
    private static let marker = Redactor.marker

    /// The Item with the exclusions applied, or `nil` when its app is
    /// excluded and its time is a gap. Applied as a Sample is written and
    /// again by the readers, so a rule added later hides past items too.
    ///
    /// The tmux session and coding agent rules see only what the Item
    /// keeps: a `session` of the form `<name>:<window>.<pane>`, and Items
    /// whose app is `Claude Code`. The live tracker applies them earlier,
    /// while it still sees the session.
    public func applied(to item: ActivityItem) -> ActivityItem? {
        if !item.appID.isEmpty, excludesApp(item.appID) {
            return nil
        }
        if isNameOnlyApp(item.appID) {
            return ActivityItem(app: item.app, appID: item.appID)
        }
        if item.app == Self.codingAgentApp, !item.location.isEmpty, isPrivateAgentPath(item.location) {
            return ActivityItem(app: item.app, appID: item.appID, session: item.session)
        }
        if let session = Self.tmuxSessionName(item.session), excludesTmuxSession(session) {
            return ActivityItem(
                app: item.app,
                appID: item.appID,
                host: item.host,
                session: Self.marker,
                workspace: Self.privateWorkspaceName
            )
        }
        var result = item
        if excludesTitle(result.window) {
            result.window = ""
        }
        if excludesAnyPath(of: result) {
            result.window = result.window.isEmpty ? "" : Self.marker
            result.location = Self.marker
            result.documents = result.documents.isEmpty ? [] : [Self.marker]
            result.command = result.command.isEmpty ? "" : Self.marker
            result.workspace = Self.privateWorkspaceName
            return result
        }
        if let host = Self.webHost(result.location) {
            if excludesDomain(host) {
                return ActivityItem(app: result.app, appID: result.appID, location: Self.marker)
            }
            if isPrivateDomain(host) {
                let domain = Self.bareDomain(host)
                result.window = ""
                result.location = (URL(string: result.location)?.scheme ?? "https") + "://" + domain
                result.workspace = domain
            }
        }
        return result
    }

    /// The block with the exclusions applied to its items; equal Items left
    /// on one device add up. `nil` when no item is left.
    public func applied(to block: ActivityBlock) -> ActivityBlock? {
        var result = block
        result.foreground = ActivityBlockItem.merged(block.foreground.compactMap(applied(to:)))
        result.background = ActivityBlockItem.merged(block.background.compactMap(applied(to:)))
        if result.foreground.isEmpty, result.background.isEmpty {
            return nil
        }
        result.reconstructedSeconds = min(block.reconstructedSeconds, result.activeSeconds)
        return result
    }

    /// The BlockItem with its Item excluded or changed.
    public func applied(to blockItem: ActivityBlockItem) -> ActivityBlockItem? {
        applied(to: blockItem.item).map { ActivityBlockItem(device: blockItem.device, seconds: blockItem.seconds, item: $0) }
    }

    // MARK: Matching

    /// The app of a coding agent's background Item (§2.3).
    public static let codingAgentApp = "Claude Code"
    static let privateWorkspaceName = ActivityItem.privateWorkspace

    /// Whether the location (a path or a `file://` URL) or a document is excluded.
    private func excludesAnyPath(of item: ActivityItem) -> Bool {
        let paths = (Self.isPath(item.location) ? [item.location] : []) + item.documents.filter(Self.isPath)
        return paths.contains(where: excludesPath)
    }

    private static func isPath(_ text: String) -> Bool {
        text.hasPrefix("/") || text.hasPrefix("~") || text.lowercased().hasPrefix("file://")
    }

    /// The host of an `http` or `https` location.
    private static func webHost(_ location: String) -> String? {
        let lowered = location.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else {
            return nil
        }
        return URL(string: location)?.host()
    }

    /// The tmux session of a `session` of the form `<name>:<window>.<pane>`.
    public static func tmuxSessionName(_ session: String) -> String? {
        guard let colon = session.lastIndex(of: ":") else {
            return nil
        }
        let target = session[session.index(after: colon)...].split(separator: ".")
        guard target.count == 2, target.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return String(session[..<colon])
    }
}
