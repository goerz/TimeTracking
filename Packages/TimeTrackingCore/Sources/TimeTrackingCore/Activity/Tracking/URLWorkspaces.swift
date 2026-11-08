// URLWorkspaces: the workspace of a web page by `[workspaces] urls`
// (activity_tracking.md §2.3 rule 4).

import Foundation

/// The first `[workspaces] urls` pattern that matches a URL names its
/// workspace by its capture group; a repository whose `origin` has that
/// name gives its folder instead.
public struct URLWorkspaces: Sendable {
    /// The patterns, compiled; one that doesn't compile is skipped.
    private let patterns: [NSRegularExpression]
    /// A repository's `origin` name (`owner/MyApp`) and its folder.
    public var repositories: [String: String]

    public init(patterns: [String], repositories: [String: String] = [:]) {
        self.patterns = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        self.repositories = repositories
    }

    /// The workspace of `url`, or `nil` when no pattern matches.
    public func workspace(of url: String) -> String? {
        let range = NSRange(url.startIndex..., in: url)
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: url, range: range) else {
                continue
            }
            let group = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            if let captured = Range(group, in: url) {
                let name = String(url[captured])
                return repositories[name] ?? name
            }
        }
        return nil
    }
}
