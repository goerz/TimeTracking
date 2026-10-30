// TrackerSettingsText: adds one value to an array of settings.toml in place,
// keeping every other byte of the file (spec_activity_tracking.md §7, §7.4).

import Foundation

/// Edits of the text of `settings.toml` that keep the user's comments,
/// order, and formatting. The file is the user's to edit; the app changes
/// it only through these edits.
public enum TrackerSettingsText {
    /// `text` with `value` appended to the string array `key` of the table
    /// `table` (`"privacy"`): at the end of an existing array, as a new key
    /// at the end of an existing table, or as a new table at the end of the
    /// file. A value already in the array leaves the text unchanged. The
    /// result is decoded to check it; a file that does not decode, or a key
    /// that is not a string array, throws.
    public static func appending(_ value: String, to key: String, in table: String, of text: String) throws(ActivityError) -> String {
        let current = try TrackerSettings(tomlText: text)
        let scanner = Scanner(text)
        let edited: String
        if let header = scanner.tableHeader(table) {
            let end = scanner.tableEnd(after: header)
            if let assignment = scanner.assignment(key, from: header, to: end) {
                guard let array = scanner.array(after: assignment) else {
                    throw .invalidSettings(notAList(key, in: table))
                }
                if array.values.contains(value) {
                    return text
                }
                edited = scanner.inserting(value, into: array)
            } else {
                edited = scanner.inserting("\(key) = [\(quoted(value))]", atEndOfTable: header, end: end)
            }
        } else {
            let separator = text.isEmpty || text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n"
            edited = text + separator + "[\(table)]\n\(key) = [\(quoted(value))]\n"
        }
        let decoded = try TrackerSettings(tomlText: edited)
        guard decoded != current else {
            throw .invalidSettings("The settings file has no list \(key) under [\(table)].")
        }
        return edited
    }

    /// "In the settings file, exclude_apps under [privacy] must be a list,
    /// like ["com.example.app"]."
    static func notAList(_ key: String, in table: String) -> String {
        let example = if key.hasSuffix("apps") {
            "com.example.app"
        } else if key.hasSuffix("domains") {
            "example.com"
        } else if key.hasSuffix("paths") {
            "~/Private"
        } else {
            "word"
        }
        let place = table.isEmpty ? key : "\(key) under [\(table)]"
        return "In the settings file, \(place) must be a list, like [\(quoted(example))]."
    }

    /// A TOML basic string.
    static func quoted(_ value: String) -> String {
        var result = "\""
        for character in value {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            default: result.append(character)
            }
        }
        return result + "\""
    }
}

extension TrackerSettingsText {
    /// An array value: the offsets of its brackets and its string elements.
    struct ArraySpan {
        var open: Int
        var close: Int
        var values: [String]
        /// The offset just past the last element, `nil` for an empty array.
        var lastElementEnd: Int?
        /// Whether a comma follows the last element.
        var trailingComma: Bool
    }

    /// A character scanner over the file that knows strings, comments, and
    /// bracket nesting, so headers and keys are found only where TOML has them.
    struct Scanner {
        let characters: [Character]

        init(_ text: String) {
            self.characters = Array(text)
        }

        /// The offset of the start of each line outside strings and arrays.
        private var topLevelLineStarts: [Int] {
            var starts = [0]
            var index = 0
            var depth = 0
            while index < characters.count {
                switch characters[index] {
                case "\"", "'":
                    index = skipString(at: index)
                    continue
                case "#":
                    index = skipComment(at: index)
                    continue
                case "[" where depth > 0 || !isLineStart(index):
                    depth += 1
                case "]" where depth > 0:
                    depth -= 1
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                case "\n" where depth == 0:
                    starts.append(index + 1)
                default:
                    break
                }
                index += 1
            }
            return starts
        }

        /// Whether only spaces precede `index` on its line.
        private func isLineStart(_ index: Int) -> Bool {
            var cursor = index - 1
            while cursor >= 0, characters[cursor] == " " || characters[cursor] == "\t" {
                cursor -= 1
            }
            return cursor < 0 || characters[cursor] == "\n"
        }

        /// The line start of the header `[table]`.
        func tableHeader(_ table: String) -> Int? {
            topLevelLineStarts.first { header(at: $0) == table }
        }

        /// The table name of a header line at `start` (`[name]`, not `[[name]]`).
        private func header(at start: Int) -> String? {
            let line = lineText(from: start).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), !line.hasPrefix("[["), let close = line.firstIndex(of: "]") else {
                return nil
            }
            let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard rest.isEmpty || rest.hasPrefix("#") else {
                return nil
            }
            return line[line.index(after: line.startIndex) ..< close].trimmingCharacters(in: .whitespaces)
        }

        /// Where the table starting at `header` ends: the next header line, or the end.
        func tableEnd(after header: Int) -> Int {
            topLevelLineStarts.first { $0 > header && self.header(at: $0) != nil } ?? characters.count
        }

        /// The offset of the `=` of `key = …` between `start` and `end`.
        func assignment(_ key: String, from start: Int, to end: Int) -> Int? {
            for lineStart in topLevelLineStarts where lineStart > start && lineStart < end {
                let line = lineText(from: lineStart)
                guard let equals = line.firstIndex(of: "=") else {
                    continue
                }
                let name = line[..<equals].trimmingCharacters(in: .whitespaces)
                let unquoted = name.count >= 2 && name.first == "\"" && name.last == "\"" ? String(name.dropFirst().dropLast()) : name
                if unquoted == key {
                    return lineStart + line.distance(from: line.startIndex, to: equals)
                }
            }
            return nil
        }

        /// The array after the `=` at `equals`, or `nil` if the value is not an array of strings.
        func array(after equals: Int) -> ArraySpan? {
            var index = equals + 1
            while index < characters.count, characters[index] == " " || characters[index] == "\t" {
                index += 1
            }
            guard index < characters.count, characters[index] == "[" else {
                return nil
            }
            var span = ArraySpan(open: index, close: index, values: [], lastElementEnd: nil, trailingComma: false)
            index += 1
            while index < characters.count {
                switch characters[index] {
                case " ", "\t", "\n", "\r":
                    index += 1
                case "#":
                    index = skipComment(at: index)
                case ",":
                    span.trailingComma = true
                    index += 1
                case "]":
                    span.close = index
                    return span
                case "\"", "'":
                    let end = skipString(at: index)
                    guard let value = decodeString(from: index, to: end) else {
                        return nil
                    }
                    span.values.append(value)
                    span.lastElementEnd = end
                    span.trailingComma = false
                    index = end
                default:
                    return nil
                }
            }
            return nil
        }

        /// The text with `value` added as the array's last element, in its layout.
        func inserting(_ value: String, into array: ArraySpan) -> String {
            let quoted = TrackerSettingsText.quoted(value)
            guard let lastEnd = array.lastElementEnd else {
                return replacing(array.open + 1 ..< array.close, with: quoted)
            }
            let inside = String(characters[array.open + 1 ..< array.close])
            if inside.contains("\n") {
                // One element per line or several per line: a new line before
                // the closing bracket, indented like the last element's line.
                let indent = indentation(ofLineContaining: lastEnd - 1)
                let comma = array.trailingComma ? "" : ","
                let closingLine = lineStart(of: array.close)
                let closeIsAlone = String(characters[closingLine ..< array.close]).trimmingCharacters(in: .whitespaces).isEmpty
                if closeIsAlone {
                    let head = String(characters[..<lastEnd]) + comma
                    let middle = String(characters[lastEnd ..< closingLine])
                    return head + middle + indent + quoted + ",\n" + String(characters[closingLine...])
                }
                return String(characters[..<lastEnd]) + comma + "\n" + indent + quoted
                    + String(characters[lastEnd...])
            }
            if array.trailingComma {
                // `["a",]` or `["a", ]`: the value goes before the bracket.
                let beforeClose = String(characters[..<array.close].reversed().drop { $0 == " " || $0 == "\t" }.reversed())
                return beforeClose + " " + quoted + String(characters[array.close...])
            }
            return String(characters[..<lastEnd]) + ", " + quoted + String(characters[lastEnd...])
        }

        /// The text with `line` added after the table's last non-blank line.
        func inserting(_ line: String, atEndOfTable header: Int, end: Int) -> String {
            var cursor = end
            // Back over the blank lines that separate this table from the next.
            while cursor > header {
                let previousLineStart = lineStart(of: cursor - 1)
                let previous = String(characters[previousLineStart ..< cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !previous.isEmpty {
                    break
                }
                cursor = previousLineStart
            }
            let prefix = String(characters[..<cursor])
            let newline = prefix.hasSuffix("\n") || prefix.isEmpty ? "" : "\n"
            return prefix + newline + line + "\n" + String(characters[cursor...])
        }

        private func replacing(_ range: Range<Int>, with text: String) -> String {
            String(characters[..<range.lowerBound]) + text + String(characters[range.upperBound...])
        }

        private func lineText(from start: Int) -> String {
            var end = start
            while end < characters.count, characters[end] != "\n" {
                end += 1
            }
            return String(characters[start ..< end])
        }

        private func lineStart(of index: Int) -> Int {
            var cursor = index
            while cursor > 0, characters[cursor - 1] != "\n" {
                cursor -= 1
            }
            return cursor
        }

        private func indentation(ofLineContaining index: Int) -> String {
            String(characters[lineStart(of: index)...].prefix { $0 == " " || $0 == "\t" })
        }

        /// The offset just past the string starting at `index` (basic,
        /// literal, or their multi-line forms).
        private func skipString(at index: Int) -> Int {
            let quote = characters[index]
            let triple = index + 2 < characters.count && characters[index + 1] == quote && characters[index + 2] == quote
            var cursor = index + (triple ? 3 : 1)
            while cursor < characters.count {
                if quote == "\"", characters[cursor] == "\\" {
                    cursor += 2
                    continue
                }
                if characters[cursor] == quote {
                    if !triple {
                        return cursor + 1
                    }
                    if cursor + 2 < characters.count, characters[cursor + 1] == quote, characters[cursor + 2] == quote {
                        return cursor + 3
                    }
                }
                if !triple, characters[cursor] == "\n" {
                    return cursor
                }
                cursor += 1
            }
            return cursor
        }

        private func skipComment(at index: Int) -> Int {
            var cursor = index
            while cursor < characters.count, characters[cursor] != "\n" {
                cursor += 1
            }
            return cursor
        }

        /// The value of a one-line basic or literal string.
        private func decodeString(from start: Int, to end: Int) -> String? {
            guard end - start >= 2 else {
                return nil
            }
            let quote = characters[start]
            let body = characters[start + 1 ..< end - 1]
            guard quote == "\"" else {
                return String(body)
            }
            var result = ""
            var escaped = false
            for character in body {
                if escaped {
                    switch character {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    default: result.append(character)
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }
            return result
        }
    }
}
