// TerminalSnapshot: the process table, tmux, and agent sessions read once
// per tick (activity_tracking.md §2.4 steps 3 and 4, §3.1).

// nil means "cannot read", which differs from an empty answer.
// swiftlint:disable discouraged_optional_collection

import Foundation

/// What the terminal sources saw at one tick.
struct TerminalSnapshot {
    var processes: ProcessTable
    var tmux: TmuxSnapshot
    /// Live Claude Code sessions by pid; `nil` without the sessions folder.
    var sessions: [Int32: AgentSession]?
    /// The tmux executable, if installed.
    var tmuxExecutable: String?

    /// Reads the table, every tmux server under the socket folder, and the sessions.
    static func read(environment: AgentEnvironment) async -> Self {
        let table = await ProcessTable(psOutput: environment.commands.run(ProcessTable.command) ?? "")
        var tmux = TmuxSnapshot()
        let executable = TmuxSnapshot.executables.first { environment.files.exists($0) }
        if let executable {
            let folder = environment.tmuxSocketFolder
            for name in (environment.files.list(folder) ?? []).sorted() {
                let socket = folder + "/" + name
                guard let clients = await environment.commands.run([
                    executable,
                    "-S",
                    socket,
                    "list-clients",
                    "-F",
                    TmuxSnapshot.clientFormat,
                ]),
                    let panes = await environment.commands.run([
                        executable,
                        "-S",
                        socket,
                        "list-panes",
                        "-a",
                        "-F",
                        TmuxSnapshot.paneFormat,
                    ])
                else {
                    continue
                }
                tmux.servers.append(socket)
                tmux.clients += TmuxSnapshot.clients(clients, server: socket)
                tmux.panes += TmuxSnapshot.panes(panes, server: socket)
            }
        }
        let sessions = AgentSessionReader.sessions(home: environment.homeDirectory, files: environment.files) { pid in
            table[pid] != nil || environment.processes.isAlive(pid)
        }
        return Self(processes: table, tmux: tmux, sessions: sessions, tmuxExecutable: executable)
    }

    /// The agent session running in the process tree of `pid`, if any.
    func session(inTreeOf pid: Int32) -> AgentSession? {
        guard let sessions else {
            return nil
        }
        if let own = sessions[pid] {
            return own
        }
        return processes.descendants(of: pid).lazy.compactMap { sessions[$0.pid] }.first
    }
}

// swiftlint:enable discouraged_optional_collection
