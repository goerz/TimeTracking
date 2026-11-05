// TrackerSourceHealth+Words: the on-screen words for the tracker's sources, their
// status, the presence state, and the primary item (design.md §11,
// activity_tracking.md §2.3, §7.4).

extension TrackerSourceHealth {
    /// The on-screen name of every source of §2.3 by id, in table order.
    public static let names: KeyValuePairs<String, String> = [
        "window": "Window titles",
        "terminal": "Terminal tab",
        "tmux": "tmux sessions",
        "editor": "File open in Neovim",
        "agents": "Coding agents",
        "tmux_events": "tmux hooks",
        "agent_events": "Claude Code hooks",
        "browser": "Browser tab",
        "history": "Browser history",
        "knowledge": "App usage history",
        "files": "Modified files",
        "shared_folder": "iCloud Drive",
        "device_events": "iPhone and iPad",
        "synced_safari": "Safari on other devices",
    ]

    /// The on-screen name of the source `id`, or `nil` for an unknown id.
    public static func name(forID id: String) -> String? {
        names.first { $0.key == id }?.value
    }

    /// The on-screen name: the library's for a known id, else the one the
    /// tracker wrote.
    public var displayName: String {
        Self.name(forID: id) ?? name
    }

    /// "On", "Limited: <reason>", or "Off: <reason>".
    public var statusText: String {
        status == .active || reason.isEmpty ? status.displayName : "\(status.displayName): \(reason)"
    }
}

extension TrackerSourceStatus {
    /// The word on screen: On, Limited, Off.
    public var displayName: String {
        switch self {
        case .active: "On"
        case .fallback: "Limited"
        case .off: "Off"
        }
    }
}

extension TrackerPresenceState {
    /// The words on screen: "In use", "Idle", "Another user is logged in".
    public var displayName: String {
        switch self {
        case .active: "In use"
        case .passive: "In use without typing"
        case .idle: "Idle"
        case .locked: "Locked"
        case .asleep: "Asleep"
        case .otherUser: "Another user is logged in"
        }
    }
}

extension TrackerPrimaryItem {
    /// The context as Activity names it: "paper (tmux)", "Safari", "Skim".
    public var contextName: String {
        let item = ActivityContext(context)
        guard item.kind == .session, !item.isPrivate else {
            return item.displayName()
        }
        return "\(item.displayName()) (tmux)"
    }

    /// "paper (tmux) · draft · nvim notes.tex".
    public var text: String {
        [context.isEmpty ? "" : contextName, subject, detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
