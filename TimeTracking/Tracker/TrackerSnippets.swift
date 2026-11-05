// TrackerSnippets: the text the Tracker pane's optional setup rows copy:
// Neovim's title, the tmux hooks, and the Claude Code hooks
// (activity_tracking.md §3.1, §7.4).

/// The snippets of the setup steps. Each event names its hook, and errors
/// stay silent: the row's mark shows whether events arrive. Every call runs
/// in the background: `tracker-event` waits for the agent's tick (over a
/// second), and Claude Code waits for its hooks (cancelling `SessionEnd`
/// hooks after 1.5 s), as tmux does without `run-shell -b`.
enum TrackerSnippets {
    static let editor = "set title titlestring=nvim\\ %F"

    /// The tmux hooks; `client-focus-in` needs `focus-events`.
    static let tmuxHooks = ["client-session-changed", "after-select-window", "after-select-pane", "client-focus-in"]

    static let tmux = (["set -g focus-events on"] + tmuxHooks.map { hook in
        "set-hook -g \(hook) 'run-shell -b \"tracker-event tmux \(hook) >/dev/null 2>&1 || true\"'"
    }).joined(separator: "\n")

    static let agentHooks = """
    {
      "hooks": {
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "tracker-event agent UserPromptSubmit >/dev/null 2>&1 &"}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "tracker-event agent Stop >/dev/null 2>&1 &"}]}],
        "SessionEnd": [{"hooks": [{"type": "command", "command": "tracker-event agent SessionEnd >/dev/null 2>&1 &"}]}]
      }
    }
    """
}
