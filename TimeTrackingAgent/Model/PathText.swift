// PathText: path arithmetic on strings (activity_tracking.md §2.2).

/// The few path operations the resolvers need, on plain strings.
nonisolated enum PathText {
    /// `notes.tex` for `/a/b/notes.tex`.
    static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// `/a/b` for `/a/b/notes.tex`; `/` for a top-level item.
    static func parent(_ path: String) -> String {
        var text = path
        while text.count > 1, text.hasSuffix("/") {
            text.removeLast()
        }
        guard let slash = text.lastIndex(of: "/") else {
            return "."
        }
        let head = String(text[..<slash])
        return head.isEmpty ? "/" : head
    }

    /// `tex` for `notes.tex`; empty without an extension.
    static func pathExtension(_ path: String) -> String {
        let name = lastComponent(path)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return ""
        }
        return String(name[name.index(after: dot)...])
    }
}
