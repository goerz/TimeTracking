// TestDates: local times for the hosted view-model tests of both apps
// (architecture.md §3).

import Foundation
import Testing
import TimeTrackingCore

/// Parses the local times the tests write out.
enum TestDates {
    /// A local time `yyyy-MM-dd'T'HH:mm[:ss]` in the current zone.
    static func date(_ text: String) throws -> Date {
        try #require(LaunchArguments.parseInstant(text, timeZone: .current), "bad date \(text)")
    }
}
