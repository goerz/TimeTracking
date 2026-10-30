// PortRegistry: notebook server ports and the panes that own them
// (spec_activity_tracking.md §2.2 rule 2, §3.1, §3.3).

import Foundation

/// Maps a `localhost` port to the item of the interpreter pane listening on it.
struct PortRegistry {
    /// How often one pane's listening ports are looked up again.
    static let rescanInterval: TimeInterval = 60
    static let lsof = "/usr/sbin/lsof"

    private var ports: [Int: SampleItem] = [:]
    private var portsByPane: [Int32: [Int]] = [:]
    private var scanned: [Int32: Date] = [:]

    /// The item of the pane that registered `port`.
    func item(forPort port: Int) -> SampleItem? {
        ports[port]
    }

    /// Whether the pane's ports are due for a lookup at `now`; marks them looked up.
    mutating func needsScan(paneOf pid: Int32, now: Date) -> Bool {
        guard now.timeIntervalSince(scanned[pid] ?? .distantPast) >= Self.rescanInterval else {
            return false
        }
        scanned[pid] = now
        return true
    }

    /// Records the ports the pane's process tree listens on.
    mutating func setPorts(_ found: [Int], paneOf pid: Int32) {
        portsByPane[pid] = found
    }

    /// The TCP ports the pane's process tree listens on, through `lsof`.
    static func listeningPorts(paneOf pid: Int32, snapshot: TerminalSnapshot, commands: any CommandRunning) async -> [Int]? {
        let pids = ([pid] + snapshot.processes.descendants(of: pid).map(\.pid)).map(String.init).joined(separator: ",")
        return await commands.run([Self.lsof, "-nP", "-a", "-p", pids, "-iTCP", "-sTCP:LISTEN", "-Fn"]).map(ports(inLsofOutput:))
    }

    /// Records `item` as the owner of the pane's ports.
    mutating func remember(_ item: SampleItem, forPaneOf pid: Int32) {
        for port in portsByPane[pid] ?? [] {
            ports[port] = item
        }
    }

    /// The ports of `lsof -Fn` lines such as `n127.0.0.1:8888` or `n*:8888`.
    static func ports(inLsofOutput output: String) -> [Int] {
        output.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("n"), let colon = line.lastIndex(of: ":") else {
                return nil
            }
            return Int(line[line.index(after: colon)...])
        }
    }
}
