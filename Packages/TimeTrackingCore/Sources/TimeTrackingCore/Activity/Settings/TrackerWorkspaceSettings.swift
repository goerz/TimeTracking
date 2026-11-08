// TrackerWorkspaceSettings: the [workspaces] table of settings.toml
// (activity_tracking.md §2.3, §7.1). A missing key takes its default.

/// `[workspaces]`: how an Item's workspace is found.
public struct TrackerWorkspaceSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case rootMarkers = "root_markers"
        case urls
    }

    /// Files or folders that mark a project's folder.
    public var rootMarkers = [
        ".git", ".hg", ".jj", "Project.toml", "pyproject.toml",
        "Package.swift", "Cargo.toml", "package.json",
    ]
    /// URL patterns, the first match wins; the capture group names the workspace.
    public var urls = [
        #"github\.com/([^/]+/[^/]+)"#,
        #"gitlab\.com/([^/]+/[^/]+)"#,
        #"^https?://(?:www\.)?([^/:?#]+)"#,
    ]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.rootMarkers = try container.value(.rootMarkers, default: fallback.rootMarkers)
        self.urls = try container.value(.urls, default: fallback.urls)
    }
}
