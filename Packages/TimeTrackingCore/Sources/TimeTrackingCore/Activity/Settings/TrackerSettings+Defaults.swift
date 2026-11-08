// TrackerSettings+Defaults: the default settings.toml, with a comment on
// every setting (activity_tracking.md §7.1).

extension TrackerSettings {
    /// The default `settings.toml`, written when the shared folder has none.
    /// Decoding it gives `TrackerSettings.defaults`.
    public static let defaultFileContents = """
    # Settings of the TimeTracking activity tracker. The tracker reads this file
    # whenever it changes and applies it within 30 seconds,
    # on this Mac and, for the exclusions, on iPhone and iPad.
    #
    # Durations: "30s", "5m", "3h". Paths: "~" is the home folder, matched
    # case-insensitively. Domains match themselves and their subdomains. Apps
    # are named by bundle identifier, such as "com.apple.Safari"; the command
    # `osascript -e 'id of app "Safari"'` prints one.

    [presence]
    # Time without input after which you count as away. Governs activity blocks
    # only; the Timer's idle prompt has its own threshold.
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
    # A block closes after this long without an attentive Sample.
    idle_close = "5m"
    # A shorter block is held, then merged into the previous one or dropped.
    min_block = "10m"
    # The split test runs once the open block is longer than this.
    split_after = "20m"
    # Credited time a change point needs on each side.
    min_half = "10m"
    # The distance (0 to 1) at which a change point splits the block.
    split_threshold = 0.7
    # The longest block.
    max_block = "90m"
    # The longest block that is mostly passive.
    max_passive_block = "3h"
    # The longest background block.
    max_background_block = "3h"
    # A background block keeps only items with at least this much time.
    min_background_item = "5m"
    # Item lines in a block's summary, and the share below which a workspace folds.
    summary_lines = 6
    summary_min_share = 0.05

    [workspaces]
    # Files or folders that mark a project's folder.
    root_markers = [
        ".git", ".hg", ".jj", "Project.toml", "pyproject.toml",
        "Package.swift", "Cargo.toml", "package.json",
    ]
    # URL patterns, the first match wins; the capture group names the workspace.
    urls = [
        'github\\.com/([^/]+/[^/]+)',
        'gitlab\\.com/([^/]+/[^/]+)',
        '^https?://(?:www\\.)?([^/:?#]+)',
    ]

    [terminal]
    # Pane titles that name the editor's file; the capture group is the path.
    title_patterns = { nvim = '^nvim (/.+)$' }
    # Programs whose panes are background items while they run.
    job_commands = ["make", "gmake", "latexmk", "pytest", "cargo", "swift", "npm"]

    [devices]
    # Visits Safari synced from other devices become activity.
    synced_safari_history = false

    [privacy]
    # Exclusions apply to what is recorded from now on, and Calendar and
    # Activity apply them to past activity when they show it. The log files
    # keep what they hold until `tracker-event reapply-exclusions <from> <to>`
    # rewrites them.

    # Files and folders at or below these paths are recorded as "(private)";
    # the time is kept.
    exclude_paths = []           # e.g. "~/Documents/Medical"
    # Paths with a folder or file name starting with one of these, likewise.
    exclude_keywords = []        # e.g. "sparsebundle"
    # tmux sessions recorded as "(private)", without window, folder, or file.
    exclude_tmux_sessions = []
    # Coding-agent sessions started in exactly these folders keep only their
    # name and app.
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

    # Redaction: the logs that leave this Mac show "(private)" in place of
    # the value after these command-line options,
    redact_options = ["--password", "--token", "--secret", "--api-key"]
    # the value of NAME=value where the name contains one of these,
    redact_names = ["TOKEN", "SECRET", "PASSWORD", "KEY"]
    # the capture group of these patterns (or the whole match without one),
    redact_patterns = ['(?i)authorization:\\s*(.+)', '://([^/@\\s]+)@']
    # the values of these query keys in addresses,
    redact_query_keys = ["token", "key", "sig", "code", "access_token", "password"]
    # and the whole query on these search sites.
    redact_query_sites = ["google.com", "duckduckgo.com", "kagi.com", "bing.com"]

    """
}
