// WezTermAdapter: the focused pane through `wezterm cli`
// (spec_activity_tracking.md §3.1).

import Foundation

/// Reads `wezterm cli list-clients --format json` (the focused pane id) and
/// `wezterm cli list --format json` (the pane's tty, title, and cwd).
nonisolated enum WezTermAdapter {
    static func focused(clients: String, panes: String) -> TerminalResolver.Located? {
        guard let clientList = try? JSONDecoder().decode([WezTermClient].self, from: Data(clients.utf8)),
              let paneList = try? JSONDecoder().decode([WezTermPane].self, from: Data(panes.utf8))
        else {
            return nil
        }
        let focusedID = clientList.min { $0.idleSeconds < $1.idleSeconds }?.focusedPaneID
        guard let pane = paneList.first(where: { $0.paneID == focusedID }) ?? paneList.first(where: \.isActive),
              !pane.ttyName.isEmpty
        else {
            return nil
        }
        return TerminalResolver.Located(tty: pane.ttyName, title: pane.title, cwd: pane.cwd.map(Self.path(fromCwd:)))
    }

    /// The path of `file://host/path`.
    static func path(fromCwd cwd: String) -> String {
        guard cwd.hasPrefix("file://"), let url = URL(string: cwd) else {
            return cwd
        }
        return url.path(percentEncoded: false)
    }
}

/// A client of `wezterm cli list-clients`.
private nonisolated struct WezTermClient: Decodable {
    enum CodingKeys: String, CodingKey {
        case focusedPaneID = "focused_pane_id"
        case idleTime = "idle_time"
    }

    var focusedPaneID: Int?
    var idleSeconds: Int

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.focusedPaneID = try container.decodeIfPresent(Int.self, forKey: .focusedPaneID)
        self.idleSeconds = try container.decodeIfPresent(WezTermDuration.self, forKey: .idleTime)?.secs ?? .max
    }
}

/// `{"secs": …, "nanos": …}`.
private nonisolated struct WezTermDuration: Decodable {
    var secs: Int
}

/// A pane of `wezterm cli list`.
private nonisolated struct WezTermPane: Decodable {
    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case ttyName = "tty_name"
        case isActive = "is_active"
        case title, cwd
    }

    var paneID: Int
    var ttyName: String
    var isActive: Bool
    var title: String?
    var cwd: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.paneID = try container.decode(Int.self, forKey: .paneID)
        self.ttyName = try container.decodeIfPresent(String.self, forKey: .ttyName) ?? ""
        self.isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
    }
}
