// TrackerSettings+Defaults: the default settings.toml, verbatim from
// spec_activity_tracking.md §7.1.

extension TrackerSettings {
    /// The default `settings.toml`, written when the shared folder has none.
    /// Decoding it gives `TrackerSettings.defaults`.
    public static let defaultFileContents = """
    # Durations: "30s", "5m", "3h". Paths: "~" is the home folder, matched
    # case-insensitively. Domains match themselves and their subdomains.

    [presence]
    # Governs activity blocks only; the Timer window's idle prompt has its own threshold.
    idle_after = "2m"
    passive_apps = [
        "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.apple.ScreenSharing", "com.apple.QuickTimePlayerX",
    ]
    passive_domains = ["youtube.com", "netflix.com", "meet.google.com"]
    passive_limit = "3h"

    [blocks]
    split_after = "20m"
    min_half = "10m"
    split_threshold = 0.7
    idle_close = "5m"
    max_block = "90m"
    max_passive_block = "3h"
    summary_lines = 6
    summary_min_share = 0.05

    [files]
    roots = ["~/Documents", "~/Desktop"]
    prune_names = [
        ".git", "node_modules", "__pycache__", ".ipynb_checkpoints", ".venv",
        "venv", "build", "_build", ".build", ".cache", ".Trash", "target",
        "DerivedData", "dist", "Pods", ".swiftpm", ".pytest_cache",
    ]
    # A folder containing one of these is a work folder (2.2).
    root_markers = [".git"]
    # Otherwise, files group under the folder this many levels below their root...
    group_depth = 1
    # ...or one level deeper below these folders, e.g. "~/Documents/Papers".
    deep_folders = []

    [terminal]
    # Pane title patterns that name the open file; the capture group is the path.
    title_patterns = { nvim = '^nvim (/.+)$' }
    # Processes recorded as coding agents (process name plus cwd).
    agent_processes = ["claude", "codex", "aider"]
    # Long-running commands recorded as secondary items.
    job_commands = ["make", "gmake", "latexmk", "pytest", "cargo", "swift", "npm"]

    [devices]
    # Blocks from Safari history synced from other devices (6.1).
    synced_safari_history = false

    [privacy]
    record_commands = false
    exclude_paths = []           # e.g. "~/Documents/Medical"
    exclude_keywords = []        # e.g. "sparsebundle"
    exclude_tmux_sessions = []
    private_agent_paths = ["~"]
    name_only_apps = ["com.1password.1password"]
    exclude_apps = []
    private_domains = []         # e.g. banks, health portals, tax services
    exclude_domains = []
    exclude_title_keywords = []

    [browser]
    summary_domain_only = ["search", "news", "shopping", "entertainment"]

    [browser.categories]
    research = ["arxiv.org", "doi.org", "scholar.google.com", "semanticscholar.org"]
    code = ["github.com", "gitlab.com", "stackoverflow.com", "readthedocs.io"]
    ai = ["claude.ai", "chatgpt.com"]
    search = ["google.com", "duckduckgo.com", "kagi.com", "bing.com"]
    news = ["nytimes.com", "theguardian.com", "news.ycombinator.com"]
    shopping = ["amazon.com", "ebay.com"]
    entertainment = ["youtube.com", "netflix.com", "reddit.com"]

    """
}
