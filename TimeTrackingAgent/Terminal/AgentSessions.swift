// AgentSessions: Claude Code's session files (spec_activity_tracking.md §2.3
// `agents`, §3.1). The format is undocumented; unknown keys are ignored.

import Foundation

/// A coding agent session from `~/.claude/sessions/<pid>.json`.
nonisolated struct AgentSession: Hashable, Sendable {
    var pid: Int32
    var name: String
    var cwd: String
    /// `session:@window.%pane`, or empty.
    var tmuxTarget: String
    var busy: Bool

    /// The tmux session of `tmuxTarget`, or empty.
    var tmuxSession: String {
        tmuxTarget.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    }
}

/// Reads the session folder. Transcripts are never read.
enum AgentSessionReader {
    static func folder(home: String) -> String {
        (home.hasSuffix("/") ? String(home.dropLast()) : home) + "/.claude/sessions"
    }

    /// The sessions of live processes, by pid.
    static func sessions(home: String, files: any FileProbe, isAlive: (Int32) -> Bool) -> [Int32: AgentSession]? {
        let folder = folder(home: home)
        guard let names = files.list(folder) else {
            return nil
        }
        var result: [Int32: AgentSession] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let pid = Int32(name.dropLast(5)), isAlive(pid), let data = files.contents(folder + "/" + name),
                  let record = try? JSONDecoder().decode(Record.self, from: data)
            else {
                continue
            }
            result[pid] = AgentSession(
                pid: pid,
                name: record.name ?? "",
                cwd: record.cwd ?? "",
                tmuxTarget: record.tmux ?? "",
                busy: record.status == "busy"
            )
        }
        return result
    }

    private struct Record: Decodable {
        var name: String?
        var cwd: String?
        var tmux: String?
        var status: String?
    }
}
