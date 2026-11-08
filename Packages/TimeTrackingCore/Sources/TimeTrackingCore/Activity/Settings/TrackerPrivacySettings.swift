// TrackerPrivacySettings: the [privacy] table of settings.toml
// (activity_tracking.md §4.3, §7.1, §7.2).

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
        case redactOptions = "redact_options"
        case redactNames = "redact_names"
        case redactPatterns = "redact_patterns"
        case redactQueryKeys = "redact_query_keys"
        case redactQuerySites = "redact_query_sites"
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
    /// The redaction filters of §4.3.
    public var redactOptions = ["--password", "--token", "--secret", "--api-key"]
    public var redactNames = ["TOKEN", "SECRET", "PASSWORD", "KEY"]
    public var redactPatterns = [#"(?i)authorization:\s*(.+)"#, #"://([^/@\s]+)@"#]
    public var redactQueryKeys = ["token", "key", "sig", "code", "access_token", "password"]
    public var redactQuerySites = ["google.com", "duckduckgo.com", "kagi.com", "bing.com"]

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
        self.redactOptions = try container.value(.redactOptions, default: fallback.redactOptions)
        self.redactNames = try container.value(.redactNames, default: fallback.redactNames)
        self.redactPatterns = try container.value(.redactPatterns, default: fallback.redactPatterns)
        self.redactQueryKeys = try container.value(.redactQueryKeys, default: fallback.redactQueryKeys)
        self.redactQuerySites = try container.value(.redactQuerySites, default: fallback.redactQuerySites)
    }
}
