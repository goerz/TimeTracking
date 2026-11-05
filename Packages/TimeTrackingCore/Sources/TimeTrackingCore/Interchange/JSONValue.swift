// JSONValue: the JSON output of the tool, with keys in the order of the
// spec's examples (automation.md §1, §8.1).

import Foundation

/// A JSON value whose objects keep their key order.
public enum JSONValue: Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([Self])
    case object([Member])

    /// One key and value of an object.
    public struct Member: Hashable, Sendable {
        public var key: String
        public var value: JSONValue

        public init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    /// An object from key-value pairs in order.
    public static func object(_ pairs: KeyValuePairs<String, Self>) -> Self {
        .object(pairs.map { Member($0.key, $0.value) })
    }

    /// A string, or `null` for `nil`.
    public static func optional(_ string: String?) -> Self {
        string.map(Self.string) ?? .null
    }

    /// The member `key` of an object.
    public subscript(key: String) -> Self? {
        guard case let .object(members) = self else {
            return nil
        }
        return members.first { $0.key == key }?.value
    }

    /// The JSON text: indented by two spaces, or on one line.
    public func text(pretty: Bool = true) -> String {
        var output = ""
        write(to: &output, indent: pretty ? 0 : nil)
        return output
    }

    private func write(to output: inout String, indent: Int?) {
        switch self {
        case .null:
            output += "null"
        case let .bool(value):
            output += value ? "true" : "false"
        case let .int(value):
            output += String(value)
        case let .double(value):
            output += value.isFinite ? String(value) : "null"
        case let .string(value):
            output += Self.quoted(value)
        case let .array(values):
            writeList(values.map { (nil, $0) }, open: "[", close: "]", to: &output, indent: indent)
        case let .object(members):
            writeList(members.map { ($0.key, $0.value) }, open: "{", close: "}", to: &output, indent: indent)
        }
    }

    private func writeList(_ items: [(String?, Self)], open: String, close: String, to output: inout String, indent: Int?) {
        guard !items.isEmpty else {
            output += open + close
            return
        }
        output += open
        for (index, (key, value)) in items.enumerated() {
            if index > 0 {
                output += ","
            }
            if let indent {
                output += "\n" + String(repeating: "  ", count: indent + 1)
            }
            if let key {
                output += Self.quoted(key) + (indent == nil ? ":" : ": ")
            }
            value.write(to: &output, indent: indent.map { $0 + 1 })
        }
        if let indent {
            output += "\n" + String(repeating: "  ", count: indent)
        }
        output += close
    }

    static func quoted(_ string: String) -> String {
        var output = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case let scalar where scalar.value < 0x20:
                output += String(format: "\\u%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
