// KeyedDecodingContainer+Settings: the decoding helpers of the settings.toml
// sections, with defaults for absent keys (activity_tracking.md §7.1).

import Foundation

extension KeyedDecodingContainer {
    /// A duration string, or `fallback` when the key is absent.
    func duration(_ key: Key, default fallback: TimeInterval) throws -> TimeInterval {
        guard contains(key) else {
            return fallback
        }
        if let text = try? decode(String.self, forKey: key) {
            guard let seconds = TrackerDuration.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "\"\(text)\" is not a duration such as \"30s\", \"5m\", or \"3h\""
                )
            }
            return seconds
        }
        return try TimeInterval(decode(Int.self, forKey: key))
    }

    /// The value at `key`, or `fallback` when the key is absent.
    func value<Value: Decodable>(_ key: Key, default fallback: Value) throws -> Value {
        try decodeIfPresent(Value.self, forKey: key) ?? fallback
    }

    /// A number written as a float or an integer, or `fallback` when absent.
    func number(_ key: Key, default fallback: Double) throws -> Double {
        guard contains(key) else {
            return fallback
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        return try Double(decode(Int.self, forKey: key))
    }
}
