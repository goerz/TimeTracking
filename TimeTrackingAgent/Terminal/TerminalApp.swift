// TerminalApp: the terminals the agent knows and their adapters
// (activity_tracking.md §3.1).

import Foundation

/// How the focused pane's terminal is found for a terminal app.
nonisolated enum TerminalAdapterKind: String, Hashable, Sendable {
    /// `wezterm cli list-clients` and `wezterm cli list`.
    case wezterm
    /// AppleScript `tty of current session of current window`.
    case iterm
    /// AppleScript `tty of selected tab of front window`.
    case terminal
}

/// A terminal app: the adapter that finds its focused pane, if any.
nonisolated struct TerminalApp: Hashable, Sendable {
    var adapter: TerminalAdapterKind?

    static let known: [String: Self] = [
        "com.github.wez.wezterm": Self(adapter: .wezterm),
        "com.googlecode.iterm2": Self(adapter: .iterm),
        "com.apple.Terminal": Self(adapter: .terminal),
        "net.kovidgoyal.kitty": Self(adapter: nil),
        "org.alacritty": Self(adapter: nil),
        "com.mitchellh.ghostty": Self(adapter: nil),
        "dev.warp.Warp-Stable": Self(adapter: nil),
    ]

    /// Where `wezterm` is installed, first match wins.
    static let weztermExecutables = [
        "/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm",
        "/Applications/WezTerm.app/Contents/MacOS/wezterm",
    ]

    static let itermScript = """
    with timeout of 1 seconds
        tell application id "com.googlecode.iterm2" to tell current session of current window to get tty
    end timeout
    """

    static let terminalScript = """
    with timeout of 1 seconds
        tell application id "com.apple.Terminal" to get tty of selected tab of front window
    end timeout
    """
}

/// Program names by role (§3.1).
nonisolated enum TerminalPrograms {
    static let editors: Set = ["nvim", "vim", "vi", "hx", "helix", "emacs", "micro", "nano", "kak"]
    static let interpreters: Set = [
        "julia", "python", "python3", "ipython", "jupyter", "jupyter-lab", "jupyter-notebook",
        "R", "node", "deno", "bun", "ruby", "irb",
    ]
    static let shells: Set = ["zsh", "bash", "fish", "sh", "nu", "tcsh", "csh", "dash", "ksh", "login"]

    /// Whether `program` is an interpreter (`python3.12` counts as `python3`).
    static func isInterpreter(_ program: String) -> Bool {
        interpreters.contains(program) || interpreters.contains(program.split(separator: ".").first.map(String.init) ?? program)
    }
}
