// ActivityItem: what attention is on, or what runs in the background
// (activity_tracking.md §2.2, §2.3).

/// An Item of a Sample or a block: the app and what in it the work is on.
///
/// Every field but `documents` is a string, and `""` means absent, as the
/// block log omits empty keys (§4.2). Equal Items are the same work, so their
/// seconds add up in a block.
public struct ActivityItem: Sendable, Hashable {
    /// The app in front, or the tool of a background item (`Claude Code`).
    public var app: String
    /// The bundle identifier, or the source of an iOS Item (`screenTime`).
    public var appID: String
    /// The window or tab title.
    public var window: String
    /// The machine the work runs on, when it is not the Sample's device.
    public var host: String
    /// The innermost named session: an agent's title, tmux's target, a chat workspace.
    public var session: String
    /// A full path or URL.
    public var location: String
    /// The files the user works on.
    public var documents: [String]
    /// The full command line of the frontmost process.
    public var command: String
    /// The project the work belongs to, as a full path or name (§2.3).
    public var workspace: String

    public init(
        app: String,
        appID: String = "",
        window: String = "",
        host: String = "",
        session: String = "",
        location: String = "",
        documents: [String] = [],
        command: String = "",
        workspace: String = ""
    ) {
        self.app = app
        self.appID = appID
        self.window = window
        self.host = host
        self.session = session
        self.location = location
        self.documents = documents
        self.command = command
        self.workspace = workspace.isEmpty ? app : workspace
    }

    /// The appID of a named Screen Time set (§2.3).
    public static let screenTimeAppID = "screenTime"
    /// The appID of the Screen Time set "Everything" (§2.3).
    public static let everythingAppID = "screenTime.everything"
    /// The workspace of an Item hidden by an exclusion (§7.2).
    public static let privateWorkspace = "private"

    /// Whether the Item is a Screen Time set's, named or "Everything".
    public var isScreenTime: Bool {
        appID == Self.screenTimeAppID || appID == Self.everythingAppID
    }

    /// The app as shown: its name, else its appID, else "Unknown app".
    /// Only converted data lacks a name.
    public var appName: String {
        if !app.isEmpty {
            return app
        }
        return appID.isEmpty ? "Unknown app" : appID
    }

    /// The workspace as shown: the last component of its path or name
    /// ("MyApp" for `~/Code/MyApp` and `owner/MyApp`), "(private)" for
    /// `private`. The workspace is empty only when the app is too, in
    /// converted data.
    public var workspaceName: String {
        Self.workspaceName(workspace.isEmpty ? appName : workspace)
    }

    /// The last component of a workspace's path or name.
    public static func workspaceName(_ workspace: String) -> String {
        if workspace == privateWorkspace {
            return "(private)"
        }
        let trimmed = workspace.hasSuffix("/") && workspace.count > 1 ? String(workspace.dropLast()) : workspace
        guard let slash = trimmed.lastIndex(of: "/") else {
            return trimmed
        }
        let last = trimmed[trimmed.index(after: slash)...]
        return last.isEmpty ? trimmed : String(last)
    }

    /// What names the item beside its app in a summary (§2.8): the first
    /// it has of a document's file name, the session, or the window.
    public var detail: String {
        if let document = documents.first(where: { !$0.isEmpty }) {
            return Self.workspaceName(document)
        }
        return session.isEmpty ? window : session
    }

    /// The item's label: its app and `detail` ("WezTerm · refactor-parser").
    public var label: String {
        detail.isEmpty ? appName : "\(appName) · \(detail)"
    }
}
