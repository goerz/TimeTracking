// TrackerPrivacySettings: the [privacy] table of settings.toml
// (spec_activity_tracking.md §7.1, §7.2).

/// `[privacy]`: what the tracker hides or never records.
public struct TrackerPrivacySettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case excludePaths = "exclude_paths"
        case excludeKeywords = "exclude_keywords"
        case excludeTmuxSessions = "exclude_tmux_sessions"
        case privateAgentPaths = "private_agent_paths"
        case nameOnlyApps = "name_only_apps"
        case excludeApps = "exclude_apps"
        case privateDomains = "private_domains"
        case excludeDomains = "exclude_domains"
        case excludeTitleKeywords = "exclude_title_keywords"
    }

    public var excludePaths: [String] = []
    public var excludeKeywords: [String] = []
    public var excludeTmuxSessions: [String] = []
    public var privateAgentPaths = ["~"]
    public var nameOnlyApps = ["com.1password.1password"]
    public var excludeApps: [String] = []
    public var privateDomains: [String] = []
    public var excludeDomains: [String] = []
    public var excludeTitleKeywords: [String] = []

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.excludePaths = try container.value(.excludePaths, default: fallback.excludePaths)
        self.excludeKeywords = try container.value(.excludeKeywords, default: fallback.excludeKeywords)
        self.excludeTmuxSessions = try container.value(.excludeTmuxSessions, default: fallback.excludeTmuxSessions)
        self.privateAgentPaths = try container.value(.privateAgentPaths, default: fallback.privateAgentPaths)
        self.nameOnlyApps = try container.value(.nameOnlyApps, default: fallback.nameOnlyApps)
        self.excludeApps = try container.value(.excludeApps, default: fallback.excludeApps)
        self.privateDomains = try container.value(.privateDomains, default: fallback.privateDomains)
        self.excludeDomains = try container.value(.excludeDomains, default: fallback.excludeDomains)
        self.excludeTitleKeywords = try container.value(.excludeTitleKeywords, default: fallback.excludeTitleKeywords)
    }
}
