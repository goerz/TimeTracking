// TrackerSettings+Defaults: the default settings.toml, verbatim from
// spec_activity_tracking.md §7.1.

extension TrackerSettings {
    /// The default `settings.toml`, written when the shared folder has none.
    /// Decoding it gives `TrackerSettings.defaults`.
    public static let defaultFileContents = """
    # Settings of the TimeTracking activity tracker. The tracker reads this file
    # whenever it changes and applies it from its next sample (every 30 seconds),
    # on this Mac and, for the exclusions, on iPhone and iPad.
    #
    # Durations: "30s", "5m", "3h". Paths: "~" is the home folder, matched
    # case-insensitively. Domains match themselves and their subdomains. Apps
    # are named by bundle identifier, such as "com.apple.Safari"; the command
    # `osascript -e 'id of app "Safari"'` prints one.

    [presence]
    # Time without input after which you count as away. Governs activity blocks
    # only; the Timer window's idle prompt has its own threshold.
    idle_after = "2m"
    # Apps and sites you watch or listen to without typing count as attention
    # while they are in front, for up to passive_limit.
    passive_apps = [
        "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.apple.ScreenSharing", "com.apple.QuickTimePlayerX",
    ]
    passive_domains = ["youtube.com", "netflix.com", "meet.google.com"]
    passive_limit = "3h"

    [blocks]
    # How the timeline is cut into blocks: a block closes after idle_close away,
    # is split in two once it is longer than split_after and its two halves (each
    # at least min_half) differ by split_threshold (0 to 1), and lasts at most
    # max_block (max_passive_block when mostly passive). Its summary lists up to
    # summary_lines items with at least summary_min_share of its time.
    split_after = "20m"
    min_half = "10m"
    split_threshold = 0.7
    idle_close = "5m"
    max_block = "90m"
    max_passive_block = "3h"
    summary_lines = 6
    summary_min_share = 0.05

    [files]
    # Watched folders: files you change below these folders are listed with the
    # block in which you changed them.
    roots = ["~/Documents", "~/Desktop"]
    # Folders with these names are not watched.
    prune_names = [
        ".git", "node_modules", "__pycache__", ".ipynb_checkpoints", ".venv",
        "venv", "build", "_build", ".build", ".cache", ".Trash", "target",
        "DerivedData", "dist", "Pods", ".swiftpm", ".pytest_cache",
    ]
    # A folder containing one of these is a work folder: its files count as one
    # piece of work.
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
    # Blocks from the Safari history of your other devices, synced through iCloud.
    synced_safari_history = false

    [privacy]
    # Exclusions apply to what is recorded from now on, and the Planner applies
    # them to past activity when it shows it. The log files keep what they hold
    # until `tracker-event reapply-exclusions <from> <to>` rewrites them.
    # Terminal command lines are never recorded; this switch has no effect.
    record_commands = false
    # Files and folders at or below these paths are recorded as "(private)";
    # the time is kept.
    exclude_paths = []           # e.g. "~/Documents/Medical"
    # Paths with a folder or file name starting with one of these, likewise.
    exclude_keywords = []        # e.g. "sparsebundle"
    # tmux sessions recorded as "tmux:(private)", without window, folder, or file.
    exclude_tmux_sessions = []
    # Coding-agent sessions started in exactly these folders keep only their
    # name and busy or idle status.
    private_agent_paths = ["~"]
    # Apps recorded by name only, without window titles or documents.
    name_only_apps = ["com.1password.1password"]
    # Apps not recorded at all; their time is a gap.
    exclude_apps = []
    # Sites recorded by domain only, without page addresses or titles.
    private_domains = []         # e.g. banks, health portals, tax services
    # Sites not recorded; the browser shows as "(private)" while one is open.
    exclude_domains = []
    # Window and tab titles containing one of these are dropped.
    exclude_title_keywords = []

    [browser]
    # Pages in these categories are summarized by domain only.
    summary_domain_only = ["search", "news", "shopping", "entertainment"]

    # Categories of sites, named after the key.
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
