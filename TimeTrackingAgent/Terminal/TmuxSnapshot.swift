// TmuxSnapshot: clients and panes of every tmux server
// (activity_tracking.md §3.1).

import Foundation

/// A tmux client: the terminal it runs on, its last input, its session.
nonisolated struct TmuxClient: Hashable, Sendable {
    var tty: String
    var activity: Date
    var session: String
    var server: String
}

/// A tmux pane with the fields the item needs.
nonisolated struct TmuxPane: Hashable, Sendable {
    var session: String
    var windowIndex: String
    var windowName: String
    var windowActive: Bool
    var paneIndex: String
    var paneActive: Bool
    var command: String
    var path: String
    var pid: Int32
    var tty: String
    /// Whether tmux names the window after its command (`automatic-rename`).
    var automaticRename: Bool
    var title: String
    var server: String

    /// Whether a window name names the pane: set by hand rather than by
    /// tmux after the program (`automatic-rename`), and not empty.
    static func windowNamesPane(_ windowName: String, automaticRename: Bool, program: String) -> Bool {
        !automaticRename && windowName != program && !windowName.isEmpty
    }

    /// Whether this pane's window name names it, with `program` its foreground program.
    func windowNamesPane(program: String) -> Bool {
        Self.windowNamesPane(windowName, automaticRename: automaticRename, program: program)
    }

    /// `session:window.pane`.
    var target: String {
        "\(session):\(windowIndex).\(paneIndex)"
    }
}

/// Every tmux server's clients and panes.
nonisolated struct TmuxSnapshot: Hashable, Sendable {
    static let clientFormat = "#{client_tty}\t#{client_activity}\t#{client_session}"
    static let paneFormat = [
        "#{session_name}", "#{window_index}", "#{window_name}", "#{window_active}", "#{pane_index}", "#{pane_active}",
        "#{pane_current_command}", "#{pane_current_path}", "#{pane_pid}", "#{pane_tty}", "#{automatic-rename}", "#{pane_title}",
    ].joined(separator: "\t")
    /// Where tmux is installed, first match wins.
    static let executables = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    var clients: [TmuxClient] = []
    var panes: [TmuxPane] = []
    /// The server sockets found.
    var servers: [String] = []

    /// The client on `tty`, if any.
    func client(onTTY tty: String) -> TmuxClient? {
        let name = ProcessTable.shortTTY(tty)
        return clients.first { ProcessTable.shortTTY($0.tty) == name }
    }

    /// The active pane of the active window of `session` on `server`.
    func activePane(session: String, server: String) -> TmuxPane? {
        panes.first { $0.server == server && $0.session == session && $0.windowActive && $0.paneActive }
    }

    /// Parses `list-clients` output of `server`.
    static func clients(_ text: String, server: String) -> [TmuxClient] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, let seconds = TimeInterval(fields[1]) else {
                return nil
            }
            return TmuxClient(tty: fields[0], activity: Date(timeIntervalSince1970: seconds), session: fields[2], server: server)
        }
    }

    /// Parses `list-panes -a` output of `server`.
    static func panes(_ text: String, server: String) -> [TmuxPane] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 11, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 12, let pid = Int32(fields[8]) else {
                return nil
            }
            return TmuxPane(
                session: fields[0],
                windowIndex: fields[1],
                windowName: fields[2],
                windowActive: fields[3] == "1",
                paneIndex: fields[4],
                paneActive: fields[5] == "1",
                command: fields[6],
                path: fields[7],
                pid: pid,
                tty: fields[9],
                automaticRename: fields[10] == "1" || fields[10] == "on",
                title: fields[11],
                server: server
            )
        }
    }
}
