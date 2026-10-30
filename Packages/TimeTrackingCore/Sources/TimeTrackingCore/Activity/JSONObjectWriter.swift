// JSONObjectWriter: JSON objects with keys in a fixed order, for the
// activity logs (spec_activity_tracking.md §4.2 to §4.4).

import Foundation

/// Builds one JSON object whose keys keep the order they were added in, so
/// the log lines read like the spec's examples.
public struct JSONObjectWriter: Sendable {
    private var members: [String] = []
    private let encoder: JSONEncoder

    public init() {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = jsonEncoder
    }

    /// Adds `key` with the JSON encoding of `value`.
    public mutating func add(_ key: String, _ value: some Encodable) {
        members.append("\(Self.quoted(key, encoder: encoder)):\(Self.json(value, encoder: encoder))")
    }

    /// Adds `key` with an already encoded JSON value.
    public mutating func addRaw(_ key: String, _ json: String) {
        members.append("\(Self.quoted(key, encoder: encoder)):\(json)")
    }

    /// The object's JSON text, without a newline.
    public var text: String {
        "{\(members.joined(separator: ","))}"
    }

    private static func quoted(_ key: String, encoder: JSONEncoder) -> String {
        json(key, encoder: encoder)
    }

    private static func json(_ value: some Encodable, encoder: JSONEncoder) -> String {
        // Strings, numbers, and arrays of them always encode; a non-finite
        // Double is the only failure and becomes null.
        guard let data = try? encoder.encode(value) else {
            return "null"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
