// Redactor: the redaction filters run over windows, locations, and commands
// when the agent writes the block log and current.json
// (activity_tracking.md §4.3).

public import Foundation

/// Replaces the secret parts of a value with `(private)` and keeps the rest.
///
/// Each filter recognizes one kind of secret: the value after an option of
/// `redact_options`, the value of `NAME=value` whose name contains an entry of
/// `redact_names`, the capture group (or whole match) of a `redact_patterns`
/// entry, the values of the query keys of `redact_query_keys`, and the whole
/// query on the sites of `redact_query_sites`.
public struct Redactor: Sendable {
    public static let marker = "(private)"

    private let options: [String]
    private let names: [String]
    private let patterns: [NSRegularExpression]
    private let queryKeys: Set<String>
    private let querySites: [String]

    public init(privacy: TrackerPrivacySettings) {
        self.options = privacy.redactOptions.filter { !$0.isEmpty }
        self.names = privacy.redactNames.map { $0.lowercased() }.filter { !$0.isEmpty }
        // A pattern that does not compile filters nothing; the settings
        // pane reports the file, not each pattern.
        self.patterns = privacy.redactPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
        self.queryKeys = Set(privacy.redactQueryKeys.map { $0.lowercased() })
        self.querySites = privacy.redactQuerySites.map { $0.lowercased() }
    }

    /// The item with its window, location, and command redacted.
    public func redacted(_ item: ActivityItem) -> ActivityItem {
        var result = item
        result.window = redacted(item.window)
        result.location = redacted(item.location)
        result.command = redacted(item.command)
        return result
    }

    /// `value` with every recognized secret replaced by `(private)`.
    public func redacted(_ value: String) -> String {
        guard !value.isEmpty else {
            return value
        }
        var text = value.split(separator: " ", omittingEmptySubsequences: false).map { redactingURLQuery(String($0)) }
            .joined(separator: " ")
        text = redactingOptions(text)
        text = redactingNamedValues(text)
        for pattern in patterns {
            text = Self.replacing(pattern, in: text)
        }
        return text
    }

    // MARK: Command lines

    /// `--token abc` and `--token=abc` become `--token (private)` and `--token=(private)`.
    private func redactingOptions(_ text: String) -> String {
        guard !options.isEmpty else {
            return text
        }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < words.count {
            let word = words[index]
            if options.contains(word), index + 1 < words.count, !words[index + 1].isEmpty {
                words[index + 1] = Self.marker
                index += 2
                continue
            }
            if let option = options.first(where: { word.hasPrefix($0 + "=") }) {
                words[index] = option + "=" + Self.marker
            }
            index += 1
        }
        return words.joined(separator: " ")
    }

    /// `API_TOKEN=abc` becomes `API_TOKEN=(private)`.
    private func redactingNamedValues(_ text: String) -> String {
        guard !names.isEmpty else {
            return text
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            guard let equals = word.firstIndex(of: "="), equals != word.startIndex else {
                return String(word)
            }
            let name = word[..<equals].lowercased()
            guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                  names.contains(where: { name.contains($0) })
            else {
                return String(word)
            }
            return word[...equals] + Self.marker
        }
        return words.joined(separator: " ")
    }

    // MARK: URLs

    /// In a word that is a URL with a query (quotes around it kept), the
    /// values of `redact_query_keys`, or the whole query on a search site.
    private func redactingURLQuery(_ word: String) -> String {
        let quotes = CharacterSet(charactersIn: "'\"")
        let text = word.trimmingCharacters(in: quotes)
        guard text.contains("://"), var components = URLComponents(string: text), let host = components.host?.lowercased(),
              let items = components.percentEncodedQueryItems, !items.isEmpty
        else {
            return word
        }
        if querySites.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            components.percentEncodedQuery = Self.marker
        } else {
            guard items.contains(where: { queryKeys.contains($0.name.lowercased()) && $0.value != nil }) else {
                return word
            }
            components.percentEncodedQueryItems = items.map { item in
                queryKeys.contains(item.name.lowercased()) && item.value != nil
                    ? URLQueryItem(name: item.name, value: Self.marker) : item
            }
        }
        guard let redacted = components.string, let range = word.range(of: text) else {
            return word
        }
        return word.replacingCharacters(in: range, with: redacted)
    }

    // MARK: Patterns

    /// Every match's first capture group, or the whole match without one,
    /// replaced by the marker.
    private static func replacing(_ pattern: NSRegularExpression, in text: String) -> String {
        let whole = NSRange(text.startIndex..., in: text)
        var result = text
        for match in pattern.matches(in: text, range: whole).reversed() {
            let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                ? match.range(at: 1) : match.range
            guard let swiftRange = Range(range, in: result) else {
                continue
            }
            result.replaceSubrange(swiftRange, with: marker)
        }
        return result
    }
}
