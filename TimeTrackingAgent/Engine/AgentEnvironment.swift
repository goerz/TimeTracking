// AgentEnvironment: everything the agent reads from the system, behind
// protocols so tests use fakes and fixtures (spec_activity_tracking.md §5,
// spec_architecture.md §3.1).

// The seams answer nil for "cannot read", which differs from an empty answer.
// swiftlint:disable discouraged_optional_collection

import Foundation
import TimeTrackingCore

/// Input and display state (`CGEventSource`, `CGSession`, `CGDisplay`).
protocol PresenceProbe {
    func read() -> PresenceReading
}

/// The frontmost app.
nonisolated struct FrontApp: Hashable, Sendable {
    var bundleID: String
    var name: String
    var pid: Int32
}

/// The focused window through Accessibility.
nonisolated struct WindowInfo: Hashable, Sendable {
    var title: String
    /// `AXDocument`, a `file://` URL or a path.
    var document: String?
    /// `AXURL` of a browser's web area.
    var url: String?

    init(title: String, document: String? = nil, url: String? = nil) {
        self.title = title
        self.document = document
        self.url = url
    }
}

/// The frontmost app and its focused window.
protocol FocusProbe {
    /// Whether the agent has the Accessibility grant.
    var isTrusted: Bool { get }

    func frontmostApp() -> FrontApp?
    /// The focused window; `nil` without Accessibility.
    func focusedWindow(of app: FrontApp) -> WindowInfo?
}

/// Runs a command (absolute executable path first) and returns its standard
/// output, or `nil` when it cannot run or fails.
protocol CommandRunning {
    func run(_ arguments: [String]) async -> String?
}

/// The outcome of an AppleScript.
nonisolated enum ScriptResult: Hashable, Sendable {
    case value(String)
    /// Automation is not granted for the target app (`-1743`).
    case denied
    case failed
}

/// Runs AppleScript (Apple Events to browsers, terminals, Finder).
protocol AppleScripting {
    func run(_ source: String) -> ScriptResult
}

/// File system reads.
protocol FileProbe {
    func exists(_ path: String) -> Bool
    func contents(_ path: String) -> Data?
    /// The names in a folder, or `nil` if it cannot be listed.
    func list(_ path: String) -> [String]?
    func modificationDate(_ path: String) -> Date?
}

/// Per-process facts beyond the `ps` table.
protocol ProcessProbe {
    func workingDirectory(of pid: Int32) -> String?
    /// The arguments, program first; `nil` if unreadable.
    func arguments(of pid: Int32) -> [String]?
    /// The last input on a terminal (its access time), e.g. for `ttys003`.
    func lastInput(onTTY tty: String) -> Date?
    func isAlive(_ pid: Int32) -> Bool
}

/// The system seams of one agent.
struct AgentEnvironment {
    var clock: any Clock
    var timeZone: TimeZone
    var homeDirectory: String
    /// The folder of tmux's server sockets (`$TMUX_TMPDIR/tmux-<uid>` or `/private/tmp/tmux-<uid>`).
    var tmuxSocketFolder: String
    /// The folder of Neovim's server sockets (`$TMPDIR/nvim.<user>`).
    var neovimSocketFolder: String
    var presence: any PresenceProbe
    var focus: any FocusProbe
    var commands: any CommandRunning
    var scripts: any AppleScripting
    var files: any FileProbe
    var processes: any ProcessProbe
    var editorRPC: any EditorRPC
    var history: any BrowserHistory
    var knowledge: any KnowledgeSource
}

// swiftlint:enable discouraged_optional_collection
