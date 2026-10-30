// SourceID: the sources of §2.3 as current.json names them
// (spec_activity_tracking.md §2.3, §4.4).

/// A source of §2.3; the raw value is its `id` in `current.json`, and the
/// cases are in table order.
nonisolated enum SourceID: String, CaseIterable, Hashable, Sendable {
    case window
    case terminal
    case tmux
    case editor
    case agents
    case tmuxEvents = "tmux_events"
    case agentEvents = "agent_events"
    case browser
    case history
    case knowledge
    case files
    case sharedFolder = "shared_folder"
    case deviceEvents = "device_events"
    case syncedSafari = "synced_safari"

    /// The display name in `current.json`.
    var name: String {
        switch self {
        case .window: "Window titles"
        case .terminal: "Terminal"
        case .tmux: "tmux"
        case .editor: "Editor file"
        case .agents: "Coding agents"
        case .tmuxEvents: "tmux hooks"
        case .agentEvents: "Agent hooks"
        case .browser: "Browsers"
        case .history: "Browser history"
        case .knowledge: "Knowledge store"
        case .files: "Modified files"
        case .sharedFolder: "iCloud Drive folder"
        case .deviceEvents: "iPhone and iPad"
        case .syncedSafari: "Synced Safari history"
        }
    }

    /// The reason shared by `history` and the browser resolver.
    static let noFullDiskAccessReason = "Full Disk Access not granted; Safari URLs keep only the domain"
}
