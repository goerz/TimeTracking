// Times and zones from text for the tests (architecture.md §3.3, §3.4).
// A typo in a test date fails the test instead of passing as another instant.

import Foundation
import Testing
import TimeTrackingCore

enum TestTime {
    // The identifiers are fixed and known to every system, so the
    // fallback is never taken.
    static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

    /// A local time `yyyy-MM-dd'T'HH:mm[:ss]` in `zone`, or RFC 3339 text
    /// with an offset; anything else fails the test.
    static func local(_ text: String, in zone: TimeZone) throws -> Date {
        try #require(LaunchArguments.parseInstant(text, timeZone: zone), "bad date \(text)")
    }

    /// An instant from RFC 3339 text with an offset.
    static func instant(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }
}
