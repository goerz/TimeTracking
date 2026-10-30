// TrackerFileSettings: the [files] table of settings.toml
// (spec_activity_tracking.md §2.2, §7.1). A missing key takes its default.

/// `[files]`: the watched roots and how files group into work folders.
public struct TrackerFileSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case roots
        case pruneNames = "prune_names"
        case rootMarkers = "root_markers"
        case groupDepth = "group_depth"
        case deepFolders = "deep_folders"
    }

    public var roots = ["~/Documents", "~/Desktop"]
    public var pruneNames = [
        ".git", "node_modules", "__pycache__", ".ipynb_checkpoints", ".venv",
        "venv", "build", "_build", ".build", ".cache", ".Trash", "target",
        "DerivedData", "dist", "Pods", ".swiftpm", ".pytest_cache",
    ]
    public var rootMarkers = [".git"]
    public var groupDepth = 1
    public var deepFolders: [String] = []

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.roots = try container.value(.roots, default: fallback.roots)
        self.pruneNames = try container.value(.pruneNames, default: fallback.pruneNames)
        self.rootMarkers = try container.value(.rootMarkers, default: fallback.rootMarkers)
        self.groupDepth = try container.value(.groupDepth, default: fallback.groupDepth)
        self.deepFolders = try container.value(.deepFolders, default: fallback.deepFolders)
    }
}
