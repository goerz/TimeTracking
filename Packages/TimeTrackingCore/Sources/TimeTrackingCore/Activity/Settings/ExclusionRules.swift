// ExclusionRules: the exclusion lists of [privacy] and their matching
// (activity_tracking.md §7.2).

public import Foundation

/// The exclusions of `settings.toml`, matched case-insensitively.
///
/// Paths may start with `~` (the home folder) and match at or below an
/// entry; keywords match a path component starting with them; domains match
/// themselves and their subdomains; agent paths match exactly.
public struct ExclusionRules: Sendable, Hashable {
    public var excludePaths: [String]
    public var excludeKeywords: [String]
    public var excludeTmuxSessions: [String]
    public var privateAgentPaths: [String]
    public var nameOnlyApps: [String]
    public var excludeApps: [String]
    public var privateDomains: [String]
    public var excludeDomains: [String]
    public var excludeTitleKeywords: [String]
    /// The folder `~` stands for.
    public var homeDirectory: String

    public init(privacy: TrackerPrivacySettings = TrackerPrivacySettings(), homeDirectory: String = NSHomeDirectory()) {
        self.excludePaths = privacy.excludePaths
        self.excludeKeywords = privacy.excludeKeywords
        self.excludeTmuxSessions = privacy.excludeTmuxSessions
        self.privateAgentPaths = privacy.privateAgentPaths
        self.nameOnlyApps = privacy.nameOnlyApps
        self.excludeApps = privacy.excludeApps
        self.privateDomains = privacy.privateDomains
        self.excludeDomains = privacy.excludeDomains
        self.excludeTitleKeywords = privacy.excludeTitleKeywords
        self.homeDirectory = homeDirectory
    }

    /// No exclusions at all.
    public static let empty: Self = {
        var privacy = TrackerPrivacySettings()
        privacy.privateAgentPaths = []
        privacy.nameOnlyApps = []
        return Self(privacy: privacy, homeDirectory: "/")
    }()

    // MARK: Paths

    /// Whether `path` (a path, `~/…`, or a `file://` URL) lies at or below
    /// an `exclude_paths` entry or has a component starting with an
    /// `exclude_keywords` entry.
    public func excludesPath(_ path: String) -> Bool {
        let normalized = normalizePath(path)
        let atOrBelow = excludePaths.contains { entry in
            let base = normalizePath(entry)
            return normalized == base || normalized.hasPrefix(base == "/" ? "/" : base + "/")
        }
        if atOrBelow {
            return true
        }
        let components = normalized.split(separator: "/")
        return excludeKeywords.contains { keyword in
            let prefix = keyword.lowercased()
            return !prefix.isEmpty && components.contains { $0.hasPrefix(prefix) }
        }
    }

    /// Whether an agent session's cwd equals a `private_agent_paths` entry.
    public func isPrivateAgentPath(_ cwd: String) -> Bool {
        let normalized = normalizePath(cwd)
        return privateAgentPaths.contains { normalizePath($0) == normalized }
    }

    // MARK: Apps, sessions, titles

    /// Whether nothing of the app with `bundleIdentifier` is recorded.
    public func excludesApp(_ bundleIdentifier: String) -> Bool {
        Self.containsFolded(excludeApps, bundleIdentifier)
    }

    /// Whether only the app name of `bundleIdentifier` is recorded.
    public func isNameOnlyApp(_ bundleIdentifier: String) -> Bool {
        Self.containsFolded(nameOnlyApps, bundleIdentifier)
    }

    /// Whether the tmux session `name` is private.
    public func excludesTmuxSession(_ name: String) -> Bool {
        Self.containsFolded(excludeTmuxSessions, name)
    }

    /// Whether `title` contains an `exclude_title_keywords` entry.
    public func excludesTitle(_ title: String) -> Bool {
        let folded = title.lowercased()
        return excludeTitleKeywords.contains { !$0.isEmpty && folded.contains($0.lowercased()) }
    }

    // MARK: Domains

    /// Whether `domain` (a host or a URL) matches `exclude_domains`.
    public func excludesDomain(_ domain: String) -> Bool {
        Self.matchesDomain(domain, excludeDomains)
    }

    /// Whether `domain` (a host or a URL) matches `private_domains`.
    public func isPrivateDomain(_ domain: String) -> Bool {
        Self.matchesDomain(domain, privateDomains)
    }

    // MARK: Helpers

    /// Expands `~`, strips `file://`, folds case, and drops a trailing slash.
    private func normalizePath(_ path: String) -> String {
        var text = path
        if text.lowercased().hasPrefix("file://"), let url = URL(string: text) {
            text = url.path(percentEncoded: false)
        }
        let home = homeDirectory.hasSuffix("/") && homeDirectory.count > 1 ? String(homeDirectory.dropLast()) : homeDirectory
        if text == "~" {
            text = home
        } else if text.hasPrefix("~/") {
            text = home + text.dropFirst()
        }
        text = text.lowercased()
        while text.count > 1, text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }

    private static func containsFolded(_ list: [String], _ value: String) -> Bool {
        let folded = value.lowercased()
        return list.contains { $0.lowercased() == folded }
    }

    /// Whether `domain` (a host or a URL) is an entry of `list` or a subdomain of one.
    public static func matchesDomain(_ domain: String, _ list: [String]) -> Bool {
        let host = normalizeDomain(domain)
        guard !host.isEmpty else {
            return false
        }
        return list.contains { entry in
            let base = normalizeDomain(entry)
            return !base.isEmpty && (host == base || host.hasSuffix("." + base))
        }
    }

    /// `host` lowercased without `www.` and a trailing dot.
    public static func bareDomain(_ host: String) -> String {
        let text = normalizeDomain(host)
        return text.hasPrefix("www.") ? String(text.dropFirst(4)) : text
    }

    static func normalizeDomain(_ domain: String) -> String {
        var text = domain.lowercased()
        if text.contains("://"), let host = URL(string: text)?.host() {
            text = host
        }
        while text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}
