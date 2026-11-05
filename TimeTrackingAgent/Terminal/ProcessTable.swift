// ProcessTable: the `ps` table the terminal sources walk
// (activity_tracking.md §3.1).

import Foundation

/// One row of `ps -axo pid=,ppid=,tty=,stat=,comm=`.
nonisolated struct ProcessEntry: Hashable, Sendable {
    var pid: Int32
    var ppid: Int32
    /// `ttys003`, or `??` without a terminal.
    var tty: String
    /// Whether the process is in its terminal's foreground process group (`+`).
    var foreground: Bool
    /// The executable path (or name) as `ps` prints `comm`.
    var path: String

    /// The executable name without folders and a login shell's leading `-`.
    var name: String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.hasPrefix("-") ? String(last.dropFirst()) : last
    }
}

/// The process table with parent links.
nonisolated struct ProcessTable: Hashable, Sendable {
    /// The `ps` invocation whose output `init(psOutput:)` parses.
    static let command = ["/bin/ps", "-axo", "pid=,ppid=,tty=,stat=,comm="]

    private(set) var entries: [Int32: ProcessEntry] = [:]
    private var children: [Int32: [Int32]] = [:]

    init(_ rows: [ProcessEntry] = []) {
        for row in rows {
            entries[row.pid] = row
            children[row.ppid, default: []].append(row.pid)
        }
        for key in children.keys {
            children[key]?.sort()
        }
    }

    /// Parses `ps` output; unreadable lines are skipped.
    init(psOutput: String) {
        var rows: [ProcessEntry] = []
        for line in psOutput.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else {
                continue
            }
            let path = fields[4].trimmingCharacters(in: .whitespaces)
            rows.append(ProcessEntry(pid: pid, ppid: ppid, tty: String(fields[2]), foreground: fields[3].contains("+"), path: path))
        }
        self.init(rows)
    }

    subscript(pid: Int32) -> ProcessEntry? {
        entries[pid]
    }

    /// Every descendant of `pid`, breadth first.
    func descendants(of pid: Int32) -> [ProcessEntry] {
        var result: [ProcessEntry] = []
        var queue = children[pid] ?? []
        var seen = Set<Int32>()
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next).inserted, let entry = entries[next] else {
                continue
            }
            result.append(entry)
            queue += children[next] ?? []
        }
        return result
    }

    /// The topmost foreground process of `tty` (a foreground process whose
    /// parent is not a foreground process of the same terminal).
    func foreground(onTTY tty: String) -> ProcessEntry? {
        let name = Self.shortTTY(tty)
        let candidates = entries.values.filter { $0.tty == name && $0.foreground }
        let top = candidates.filter { candidate in
            guard let parent = entries[candidate.ppid] else {
                return true
            }
            return !(parent.tty == name && parent.foreground)
        }
        return top.max { $0.pid < $1.pid } ?? candidates.max { $0.pid < $1.pid }
    }

    /// The terminals of `pid`'s descendants.
    func terminals(below pid: Int32) -> [String] {
        Array(Set(descendants(of: pid).map(\.tty).filter { $0 != "??" && !$0.isEmpty })).sorted()
    }

    /// `ttys003` for `/dev/ttys003` or `ttys003`.
    static func shortTTY(_ tty: String) -> String {
        tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
    }
}
