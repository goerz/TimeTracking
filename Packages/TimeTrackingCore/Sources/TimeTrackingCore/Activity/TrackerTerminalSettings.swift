// TrackerTerminalSettings: the [terminal] table of settings.toml
// (spec_activity_tracking.md §3.1, §7.1). A missing key takes its default.

/// `[terminal]`: editor title patterns, coding agents, and job commands.
public struct TrackerTerminalSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case titlePatterns = "title_patterns"
        case agentProcesses = "agent_processes"
        case jobCommands = "job_commands"
    }

    /// Pane title patterns by process; the capture group is the path.
    public var titlePatterns = ["nvim": "^nvim (/.+)$"]
    public var agentProcesses = ["claude", "codex", "aider"]
    public var jobCommands = ["make", "gmake", "latexmk", "pytest", "cargo", "swift", "npm"]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.titlePatterns = try container.value(.titlePatterns, default: fallback.titlePatterns)
        self.agentProcesses = try container.value(.agentProcesses, default: fallback.agentProcesses)
        self.jobCommands = try container.value(.jobCommands, default: fallback.jobCommands)
    }
}
