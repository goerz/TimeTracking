// ActivityContext+Display: the names of apps, sessions, sites, folders, and
// devices on screen, never the log's keys (spec_planner_activity.md §1.3;
// spec_design.md §12).

extension ActivityContext {
    /// App contexts whose name is not the context capitalized.
    public static let appNames: [String: String] = [
        "bbedit": "BBEdit", "chatgpt": "ChatGPT", "devonthink": "DEVONthink", "facetime": "FaceTime",
        "iterm2": "iTerm2", "macvim": "MacVim", "obs": "OBS", "omnifocus": "OmniFocus", "powerpoint": "PowerPoint",
        "pycharm": "PyCharm", "textedit": "TextEdit", "texshop": "TeXShop", "vlc": "VLC", "vscode": "VS Code",
        "webstorm": "WebStorm", "wezterm": "WezTerm", "1password": "1Password",
    ]

    /// The name of an app context without an installed app's name: the
    /// table's, else every word capitalized ("activity monitor" reads
    /// "Activity Monitor"). A name with a capital letter is kept as written.
    public static func appDisplayName(_ context: String) -> String {
        if let name = appNames[context] {
            return name
        }
        guard context == context.lowercased() else {
            return context
        }
        return context.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The name where no badge marks a session: "paper (tmux)", "Safari",
    /// "VS Code".
    public func label(bundleIdentifier: String? = nil, appName: (String) -> String? = { _ in nil }) -> String {
        let display = displayName(bundleIdentifier: bundleIdentifier, appName: appName)
        return kind == .session && !isPrivate ? "\(display) (tmux)" : display
    }

    /// A group key as Activity shows it: a session "paper (tmux)", a browser
    /// or app by its name, a site ("github.com/owner") or folder
    /// ("~/Papers/2026_Noise") as written, and `private` as "(private)".
    public static func groupKeyName(_ key: String) -> String {
        if key == "private" {
            return "(private)"
        }
        if key.hasPrefix("tmux:") || browsers[key] != nil {
            return ActivityContext(key).label()
        }
        if key.hasPrefix("/") || key.hasPrefix("~") || key.contains(".") || key.contains("/") {
            return key
        }
        return ActivityContext(key).displayName()
    }

    /// A device as the Activity section and the Calendar name it: `remote`
    /// (synced Safari history of no known device) reads "Other devices (Safari)".
    public static func deviceName(_ device: String) -> String {
        device == "remote" ? "Other devices (Safari)" : device
    }
}
