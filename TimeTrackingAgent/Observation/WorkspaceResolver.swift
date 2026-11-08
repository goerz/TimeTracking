// WorkspaceResolver: the workspace rules of §2.3 over this Mac's disk:
// root markers, git worktrees, repository origins, notebook servers
// (activity_tracking.md §2.3).

import Foundation
import TimeTrackingCore

/// Gives Items their workspace. It knows the repositories among the
/// Samples' workspaces by their `origin` remote, seeded from the stored
/// Samples at start and extended as new ones show up.
@MainActor
final class WorkspaceResolver {
    private let environment: AgentEnvironment
    private var settings: TrackerWorkspaceSettings
    private var rules: WorkspaceRules
    /// A repository's `origin` name (`owner/MyApp`) and its folder.
    private(set) var repositories: [String: String] = [:]
    private var inspected: Set<String> = []

    init(environment: AgentEnvironment, settings: TrackerWorkspaceSettings) {
        self.environment = environment
        self.settings = settings
        self.rules = Self.rules(settings, environment: environment)
    }

    /// The workspace of `item`; a `localhost` page takes the folder of the
    /// server on its port from `ports`.
    func workspace(of item: ActivityItem, settings: TrackerWorkspaceSettings, ports: PortRegistry) -> String {
        if settings != self.settings {
            self.settings = settings
            rules = Self.rules(settings, environment: environment)
        }
        rules.urls.repositories = repositories
        let workspace = rules.workspace(of: item) { ports.folder(forPort: $0) }
        learn(workspace)
        return workspace
    }

    /// The URL patterns with the known repositories, for iOS Safari tabs.
    func urlWorkspaces(settings: TrackerWorkspaceSettings) -> URLWorkspaces {
        URLWorkspaces(patterns: settings.urls, repositories: repositories)
    }

    /// Learns the `origin` names of the repository folders among `workspaces`.
    func learn(_ workspaces: some Sequence<String>) {
        for workspace in workspaces {
            learn(workspace)
        }
    }

    private func learn(_ workspace: String) {
        guard workspace.hasPrefix("/") || workspace.hasPrefix("~"), inspected.insert(workspace).inserted else {
            return
        }
        let folder = HomePaths(home: environment.homeDirectory).expand(workspace)
        guard let config = environment.files.contents(folder + "/.git/config").map({ String(decoding: $0, as: UTF8.self) }),
              let name = Self.originName(gitConfig: config)
        else {
            return
        }
        repositories[name] = workspace
    }

    /// `owner/MyApp` of the `origin` remote's URL in a git config:
    /// `git@github.com:owner/MyApp.git` or `https://github.com/owner/MyApp`.
    static func originName(gitConfig: String) -> String? {
        var inOrigin = false
        for line in gitConfig.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                inOrigin = line == #"[remote "origin"]"#
                continue
            }
            guard inOrigin, line.hasPrefix("url"), let equals = line.firstIndex(of: "=") else {
                continue
            }
            var url = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if url.hasSuffix(".git") {
                url.removeLast(4)
            }
            let path = url.contains("://") ? URL(string: url)?.path() ?? "" : String(url.split(separator: ":").last ?? "")
            let parts = path.split(separator: "/").suffix(2)
            return parts.count == 2 ? parts.joined(separator: "/") : nil
        }
        return nil
    }

    private static func rules(_ settings: TrackerWorkspaceSettings, environment: AgentEnvironment) -> WorkspaceRules {
        let files = environment.files
        let markers = settings.rootMarkers
        return WorkspaceRules(
            settings: settings,
            homeDirectory: environment.homeDirectory,
            hasRootMarker: { folder in markers.contains { files.exists("\(folder)/\($0)") } },
            mainRepository: { folder in
                // A worktree's `.git` is a file: `gitdir: <main>/.git/worktrees/<name>`.
                guard let data = files.contents(folder + "/.git"), let text = String(data: data, encoding: .utf8),
                      text.hasPrefix("gitdir:"), let range = text.range(of: "/.git/worktrees/")
                else {
                    return nil
                }
                return text.dropFirst("gitdir:".count)[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            }
        )
    }
}
