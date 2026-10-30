// SuggestionTokens: the tokens of contexts, subjects, details, group keys,
// and calendar titles (spec_planner_calendar.md §5.2).

/// Tokenization of §5.2.
public enum SuggestionTokens {
    /// `c:`, `s:`, `d:`, and `g:` tokens of one item and its block's group key.
    public static func tokens(of item: ActivityItem) -> Set<String> {
        var result = Set<String>()
        result.formUnion(pieces(item.context, coarse: [" "]).map { "c:" + $0 })
        if ActivityContext(item.context).kind == .browser, !item.subject.hasPrefix("/"), !item.subject.hasPrefix("~") {
            result.formUnion(sitePrefixes(item.subject).map { "s:" + $0 })
        } else {
            result.formUnion(pieces(item.subject, coarse: [" ", "/"]).map { "s:" + $0 })
        }
        result.formUnion(pieces(item.detail, coarse: [" ", "/"]).map { "d:" + $0 })
        return result
    }

    /// `g:<group key>`.
    public static func groupToken(_ groupKey: String) -> String {
        "g:" + groupKey.lowercased()
    }

    /// `k:` tokens of a calendar title (words, no full string).
    public static func titleTokens(_ title: String?) -> Set<String> {
        guard let title else {
            return []
        }
        return Set(split(title.lowercased(), on: [" ", "/", ":", ".", "_", "-"]).filter(keep).map { "k:" + $0 })
    }

    /// The full lowercased string, its coarse pieces (split on `coarse`), and
    /// their fine pieces (`:`, `.`, `_`, `-`, camel case), without pieces under
    /// two characters or numbers of four or more digits.
    static func pieces(_ text: String, coarse separators: Set<Character>) -> Set<String> {
        guard !text.isEmpty else {
            return []
        }
        var result: Set<String> = [text.lowercased()]
        for piece in split(text, on: separators) {
            result.insert(piece.lowercased())
            for fine in split(piece, on: [":", ".", "_", "-"]).flatMap(camelCaseWords) {
                result.insert(fine.lowercased())
            }
        }
        return result.filter(keep)
    }

    /// `github.com`, `github.com/owner`, `github.com/owner/repo`.
    static func sitePrefixes(_ subject: String) -> [String] {
        let parts = subject.lowercased().split(separator: "/").map(String.init)
        return parts.indices.map { parts[...$0].joined(separator: "/") }.filter(keep)
    }

    private static func keep(_ piece: String) -> Bool {
        piece.count >= 2 && !(piece.count >= 4 && piece.allSatisfy(\.isNumber))
    }

    private static func split(_ text: String, on separators: Set<Character>) -> [String] {
        text.split { separators.contains($0) }.map(String.init)
    }

    /// "TimeTracking" → "Time", "Tracking"; "parseURL" → "parse", "URL".
    static func camelCaseWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let lowerToUpper = character.isUppercase && (previous?.isLowercase ?? false)
            let acronymEnd = character.isUppercase && (previous?.isUppercase ?? false) && (next?.isLowercase ?? false)
            if !current.isEmpty, lowerToUpper || acronymEnd {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}
