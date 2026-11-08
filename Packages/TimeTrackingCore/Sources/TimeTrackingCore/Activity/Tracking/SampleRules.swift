// SampleRules: what every write of Samples needs (activity_tracking.md §4.1, §7.2).

public import Foundation

/// What every write needs: the exclusions applied as a Sample is written,
/// the zone of new dates, and how far past 00:00 a date's pass reads.
public struct SampleRules: Sendable {
    public var exclusions: ExclusionRules
    public var zone: TimeZone
    /// `max_passive_block`: a Sample this soon after a date's 00:00 also marks the date before.
    public var maxPassiveBlock: TimeInterval

    public init(exclusions: ExclusionRules, zone: TimeZone, maxPassiveBlock: TimeInterval) {
        self.exclusions = exclusions
        self.zone = zone
        self.maxPassiveBlock = maxPassiveBlock
    }
}
