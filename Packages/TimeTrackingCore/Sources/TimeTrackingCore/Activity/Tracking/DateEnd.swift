// DateEnd: where a date's last block ends, or that the date is unsettled
// (activity_tracking.md §2.7).

public import Foundation

/// Where a date's last block ends, or that the date is unsettled (§2.7).
public enum DateEnd: Sendable, Hashable, Codable {
    /// The end of the date's last block, foreground or background; `nil` without a block.
    case settled(Date?)
    case unsettled
}
