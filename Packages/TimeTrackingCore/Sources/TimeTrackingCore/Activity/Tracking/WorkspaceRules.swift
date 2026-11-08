// WorkspaceRules: the project an Item's work belongs to
// (activity_tracking.md §2.3).

import Foundation

/// The rules of §2.3, the first that applies giving the workspace: a host
/// prefixes the location; a path takes its nearest folder with a root
/// marker (a git worktree resolved to its main repository), else its own
/// folder, never the home folder; a `localhost` URL takes the workspace of
/// the folder its server runs in; another URL the first pattern of
/// `[workspaces] urls` that matches, or the repository whose `origin` has
/// that name; anything else the app.
///
/// The disk is reached only through the closures, so the rules are pure.
public struct WorkspaceRules {
    private let homeDirectory: String
    /// Whether a folder holds one of the root markers.
    private let hasRootMarker: (String) -> Bool
    /// The main repository of a git worktree folder, or `nil` for any other.
    private let mainRepository: (String) -> String?
    /// The URL patterns and the known repositories.
    public var urls: URLWorkspaces

    public init(
        settings: TrackerWorkspaceSettings,
        homeDirectory: String,
        hasRootMarker: @escaping (String) -> Bool,
        mainRepository: @escaping (String) -> String?
    ) {
        self.urls = URLWorkspaces(patterns: settings.urls)
        self.homeDirectory = homeDirectory
        self.hasRootMarker = hasRootMarker
        self.mainRepository = mainRepository
    }

    /// The workspace of `item`; `localhostFolder` gives the working folder
    /// of the server on a local port.
    public func workspace(of item: ActivityItem, localhostFolder: (Int) -> String? = { _ in nil }) -> String {
        if !item.host.isEmpty, !item.location.isEmpty {
            return "\(item.host):\(item.location)"
        }
        let path = item.documents.first.map(Self.folder) ?? item.location
        if Self.isPath(path), let folder = workspace(ofPath: path) {
            return folder
        }
        if let url = URL(string: item.location), let host = url.host()?.lowercased() {
            if host == "localhost" || host == "127.0.0.1", let port = url.port, let folder = localhostFolder(port),
               let workspace = workspace(ofPath: folder)
            {
                return workspace
            }
            if let workspace = urls.workspace(of: item.location) {
                return workspace
            }
        }
        return item.app
    }

    /// The nearest enclosing folder with a root marker (a worktree resolved
    /// to its main repository), else the path's own folder; `nil` when that
    /// is the home folder.
    public func workspace(ofPath path: String) -> String? {
        let home = Self.trimmed(homeDirectory)
        let expanded = Self.trimmed(path.hasPrefix("~") ? home + path.dropFirst() : path)
        var folder = expanded
        while folder.count > 1, folder != home {
            if hasRootMarker(folder) {
                return tilde(mainRepository(folder) ?? folder, home: home)
            }
            folder = Self.folder(folder)
        }
        return expanded == home ? nil : tilde(expanded, home: home)
    }

    private func tilde(_ path: String, home: String) -> String {
        path == home || !path.hasPrefix(home + "/") ? path : "~" + path.dropFirst(home.count)
    }

    private static func isPath(_ text: String) -> Bool {
        text.hasPrefix("/") || text.hasPrefix("~")
    }

    /// The folder holding `path`.
    static func folder(_ path: String) -> String {
        let trimmed = trimmed(path)
        guard let slash = trimmed.lastIndex(of: "/") else {
            return trimmed
        }
        return slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
