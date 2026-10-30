// BrowserItemRules: how a browser URL becomes an item (spec_activity_tracking.md
// §2.2 rule 4, §3.3, §7.2). Shared by the Mac agent and the iOS web extension.

import Foundation

/// Turns a tab's URL into subject, detail, and group key.
///
/// Code hosts give `host/owner/repo` as subject and `host/owner` as group
/// key; other URLs the bare domain. Summaries drop query and fragment
/// except a forum topic id, and domains of the `summary_domain_only`
/// categories keep only the domain. `exclude_domains` makes the item
/// `<browser> (private)`; `private_domains` keep only the domain everywhere.
public struct BrowserItemRules: Sendable, Hashable {
    /// Hosts whose first two path components name owner and repository.
    public static let codeHosts = ["github.com", "gitlab.com", "bitbucket.org", "codeberg.org"]
    /// Query keys kept in a summary (forum topic ids).
    public static let keptQueryKeys = ["t", "topic", "tid"]

    public var settings: TrackerBrowserSettings
    public var exclusions: ExclusionRules

    public init(settings: TrackerBrowserSettings = TrackerBrowserSettings(), exclusions: ExclusionRules = .empty) {
        self.settings = settings
        self.exclusions = exclusions
    }

    /// The parts of a browser item.
    public struct Parts: Sendable, Hashable {
        public var subject: String
        public var detail: String
        public var groupKey: String
        /// The bare domain, e.g. `github.com` or `localhost:8888`.
        public var domain: String
        /// Whether the URL is on an `exclude_domains` domain (the item is private).
        public var isExcluded: Bool
        /// The URL the detail log may keep: the full URL, only the domain for
        /// `private_domains`, `nil` for `exclude_domains`.
        public var loggedURL: String?

        public init(subject: String, detail: String, groupKey: String, domain: String, isExcluded: Bool, loggedURL: String?) {
            self.subject = subject
            self.detail = detail
            self.groupKey = groupKey
            self.domain = domain
            self.isExcluded = isExcluded
            self.loggedURL = loggedURL
        }
    }

    /// The parts for `urlText`, or `nil` when it is not an http(s) URL with a host.
    public func parts(for urlText: String) -> Parts? {
        guard let components = URLComponents(string: urlText),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = components.host, !rawHost.isEmpty
        else {
            return nil
        }
        let domain = Self.bareDomain(rawHost) + (components.port.map { ":\($0)" } ?? "")
        if exclusions.excludesDomain(rawHost) {
            return Parts(subject: "", detail: "", groupKey: domain, domain: domain, isExcluded: true, loggedURL: nil)
        }
        if exclusions.isPrivateDomain(rawHost) {
            return Parts(subject: domain, detail: "", groupKey: domain, domain: domain, isExcluded: false, loggedURL: "\(scheme)://\(rawHost)")
        }
        let path = components.path.split(separator: "/").map(String.init)
        if domainOnly(rawHost) {
            return Parts(subject: domain, detail: "", groupKey: domain, domain: domain, isExcluded: false, loggedURL: urlText)
        }
        if Self.codeHosts.contains(Self.bareDomain(rawHost)), let owner = path.first {
            let repo = path.count > 1 ? "/\(path[1])" : ""
            let rest = Self.codeHostDetail(Array(path.dropFirst(2)))
            return Parts(
                subject: "\(domain)/\(owner)\(repo)",
                detail: rest,
                groupKey: "\(domain)/\(owner)",
                domain: domain,
                isExcluded: false,
                loggedURL: urlText
            )
        }
        var detail = path.joined(separator: "/")
        if let topic = components.queryItems?.first(where: { Self.keptQueryKeys.contains($0.name.lowercased()) }), let value = topic.value {
            detail += "?\(topic.name)=\(value)"
        }
        return Parts(subject: domain, detail: detail, groupKey: domain, domain: domain, isExcluded: false, loggedURL: urlText)
    }

    /// Whether `host` is in a category of `summary_domain_only`.
    public func domainOnly(_ host: String) -> Bool {
        settings.summaryDomainOnly.contains { category in
            Self.matchesDomain(host, settings.categories[category] ?? [])
        }
    }

    /// `host` lowercased without `www.` and a trailing dot.
    public static func bareDomain(_ host: String) -> String {
        var text = host.lowercased()
        while text.hasSuffix(".") {
            text.removeLast()
        }
        if text.hasPrefix("www.") {
            text.removeFirst(4)
        }
        return text
    }

    /// Whether `host` (or the host of a URL) is a domain of `list` or a subdomain of one.
    public static func matchesDomain(_ host: String, _ list: [String]) -> Bool {
        var text = host.lowercased()
        if text.contains("://"), let parsed = URL(string: text)?.host() {
            text = parsed
        }
        while text.hasSuffix(".") {
            text.removeLast()
        }
        guard !text.isEmpty else {
            return false
        }
        return list.contains { entry in
            let base = entry.lowercased()
            return !base.isEmpty && (text == base || text.hasSuffix("." + base))
        }
    }

    /// A code host path after owner and repository: pull requests and
    /// issues reduce to their number, everything else stays.
    private static func codeHostDetail(_ path: [String]) -> String {
        if path.count >= 2, ["pull", "pulls", "issues", "merge_requests"].contains(path[0]) {
            return "\(path[0])/\(path[1])"
        }
        if path.count >= 3, path[0] == "-", path[1] == "merge_requests" || path[1] == "issues" {
            return "\(path[1])/\(path[2])"
        }
        return path.joined(separator: "/")
    }
}
