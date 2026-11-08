// LocatedPane: the focused pane a terminal adapter found
// (activity_tracking.md §3.1).

/// The focused pane's tty, and its title and working folder when the
/// adapter knows them. `cwdHost` is the host of an OSC 7 report from a
/// remote shell, empty for this Mac.
nonisolated struct LocatedPane: Hashable, Sendable {
    var tty: String
    var title: String?
    var cwd: String?
    var cwdHost = ""
}
