// Anonymizer: placeholders for home-directory paths, host names, and URL
// paths in `--record` output (activity_tracking.md §5, TRK-30).

import Foundation

/// Replaces personal strings with stable placeholders: each path component
/// below the home folder becomes `dN` (files `fN.ext`), the user and host
/// names become `user` and `host`, and every URL path segment becomes `pN`
/// (numbers stay, query and fragment go). The same input always gets the
/// same placeholder within one run, so fixtures stay consistent.
struct Anonymizer {
    let homeDirectory: String
    let userName: String
    let hostNames: [String]
    private var components: [String: String] = [:]
    private var segments: [String: String] = [:]

    init(homeDirectory: String, userName: String, hostNames: [String]) {
        self.homeDirectory = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        self.userName = userName
        // Longest first, so `alex-mac.local` goes before `alex-mac`.
        self.hostNames = hostNames.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    /// Anonymizes free text: adapter outputs and sample lines.
    mutating func text(_ input: String) -> String {
        var output = input
        output = replaceURLs(output)
        output = replacePaths(output, prefix: homeDirectory)
        output = replacePaths(output, prefix: "~")
        for host in hostNames {
            output = output.replacing(host, with: "host")
        }
        if !userName.isEmpty {
            output = output.replacing(userName, with: "user")
        }
        return output
    }

    /// Anonymizes a browser subject such as `github.com/owner/repo` or a
    /// detail such as `pull/123`: every path segment but numbers.
    mutating func urlPath(_ path: String, keepFirst: Bool) -> String {
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for index in parts.indices where !(keepFirst && index == 0) {
            parts[index] = segment(parts[index])
        }
        return parts.joined(separator: "/")
    }

    // MARK: Helpers

    private mutating func segment(_ value: String) -> String {
        guard !value.isEmpty, Int(value) == nil else {
            return value
        }
        if let known = segments[value] {
            return known
        }
        let placeholder = "p\(segments.count + 1)"
        segments[value] = placeholder
        return placeholder
    }

    private mutating func component(_ value: String) -> String {
        guard !value.isEmpty else {
            return value
        }
        if let known = components[value] {
            return known
        }
        let ext = PathText.pathExtension(value)
        let number = components.count + 1
        let placeholder = ext.isEmpty || ext.count > 5 ? "d\(number)" : "f\(number).\(ext)"
        components[value] = placeholder
        return placeholder
    }

    /// Replaces the components after `prefix/` up to a delimiter.
    private mutating func replacePaths(_ input: String, prefix: String) -> String {
        guard !prefix.isEmpty, input.contains(prefix) else {
            return input
        }
        var output = ""
        var rest = Substring(input)
        while let range = rest.range(of: prefix) {
            output += rest[..<range.lowerBound]
            output += prefix == homeDirectory ? "/Users/user" : prefix
            rest = rest[range.upperBound...]
            guard rest.first == "/" else {
                continue
            }
            let end = rest.firstIndex { Self.delimiters.contains($0) } ?? rest.endIndex
            let path = rest[..<end]
            let mapped = path.split(separator: "/", omittingEmptySubsequences: false).map { component(String($0)) }
            output += mapped.joined(separator: "/")
            rest = rest[end...]
        }
        return output + rest
    }

    private static let delimiters: Set<Character> = ["\"", "\t", "\n", "'", ",", "]", ")", " "]

    private mutating func replaceURLs(_ input: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(https?://[^/\s"']+)(/[^\s"'\]\)]*)?"#) else {
            return input
        }
        var output = ""
        var cursor = input.startIndex
        for match in expression.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
            guard let whole = Range(match.range, in: input), let hostRange = Range(match.range(at: 1), in: input) else {
                continue
            }
            output += input[cursor ..< whole.lowerBound]
            output += input[hostRange]
            if let pathRange = Range(match.range(at: 2), in: input) {
                var path = String(input[pathRange])
                if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
                    path = String(path[..<cut])
                }
                output += urlPath(path, keepFirst: false)
            }
            cursor = whole.upperBound
        }
        return output + input[cursor...]
    }
}
