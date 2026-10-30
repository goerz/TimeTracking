// WezTermAdapter: the focused pane through `wezterm cli`
// (spec_activity_tracking.md §3.1).

import Foundation

/// Reads `wezterm cli list-clients --format json` (the focused pane id) and
/// `wezterm cli list --format json` (the pane's tty, title, and cwd).
nonisolated enum WezTermAdapter {
    static func focused(clients: String, panes: String) -> TerminalResolver.Located? {
        guard let clientList = try? JSONDecoder().decode([Client].self, from: Data(clients.utf8)),
              let paneList = try? JSONDecoder().decode([Pane].self, from: Data(panes.utf8))
        else {
            return nil
        }
        let focusedID = clientList.min { ($0.idleTime?.secs ?? .max) < ($1.idleTime?.secs ?? .max) }?.focusedPaneID
        guard let pane = paneList.first(where: { $0.paneID == focusedID }) ?? paneList.first(where: { $0.isActive == true }),
              let tty = pane.ttyName, !tty.isEmpty
        else {
            return nil
        }
        return TerminalResolver.Located(tty: tty, title: pane.title, cwd: pane.cwd.map(Self.path(fromCwd:)))
    }

    /// The path of `file://host/path`.
    static func path(fromCwd cwd: String) -> String {
        guard cwd.hasPrefix("file://"), let url = URL(string: cwd) else {
            return cwd
        }
        return url.path(percentEncoded: false)
    }

    private struct Client: Decodable {
        enum CodingKeys: String, CodingKey {
            case focusedPaneID = "focused_pane_id"
            case idleTime = "idle_time"
        }

        var focusedPaneID: Int?
        var idleTime: Duration?
    }

    private struct Duration: Decodable {
        var secs: Int
    }

    private struct Pane: Decodable {
        enum CodingKeys: String, CodingKey {
            case paneID = "pane_id"
            case ttyName = "tty_name"
            case isActive = "is_active"
            case title, cwd
        }

        var paneID: Int
        var ttyName: String?
        var isActive: Bool?
        var title: String?
        var cwd: String?
    }
}
