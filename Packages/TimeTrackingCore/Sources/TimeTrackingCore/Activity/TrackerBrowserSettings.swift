// TrackerBrowserSettings: the [browser] table of settings.toml with
// [browser.categories] (activity_tracking.md §3.3, §7.1). A missing key
// takes its default.

/// `[browser]`: domain categories and which of them summarize to the domain.
public struct TrackerBrowserSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case summaryDomainOnly = "summary_domain_only"
        case categories
    }

    public var summaryDomainOnly = ["search", "news", "shopping", "entertainment"]
    /// Domains per category.
    public var categories = [
        "research": ["arxiv.org", "doi.org", "scholar.google.com", "semanticscholar.org"],
        "code": ["github.com", "gitlab.com", "stackoverflow.com", "readthedocs.io"],
        "ai": ["claude.ai", "chatgpt.com"],
        "search": ["google.com", "duckduckgo.com", "kagi.com", "bing.com"],
        "news": ["nytimes.com", "theguardian.com", "news.ycombinator.com"],
        "shopping": ["amazon.com", "ebay.com"],
        "entertainment": ["youtube.com", "netflix.com", "reddit.com"],
    ]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.summaryDomainOnly = try container.value(.summaryDomainOnly, default: fallback.summaryDomainOnly)
        self.categories = try container.value(.categories, default: fallback.categories)
    }
}
