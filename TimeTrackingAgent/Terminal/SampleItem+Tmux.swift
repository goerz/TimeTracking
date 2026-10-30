// SampleItem+Tmux: the `tmux:<session>` context of a session's items
// (spec_activity_tracking.md §2.2, §3.1).

extension SampleItem {
    /// What every tmux context starts with.
    nonisolated static let tmuxPrefix = "tmux:"

    /// `tmux:<session>`, the context and group key of a session's items.
    nonisolated static func tmuxContext(_ session: String) -> String {
        tmuxPrefix + session
    }

    /// The session of a `tmux:<session>` context; `nil` for any other context.
    nonisolated static func tmuxSession(ofContext context: String) -> String? {
        context.hasPrefix(tmuxPrefix) ? String(context.dropFirst(tmuxPrefix.count)) : nil
    }

    /// Whether the item is a tmux session's.
    nonisolated var isTmux: Bool {
        context.hasPrefix(Self.tmuxPrefix)
    }
}
