// ActivityReading: the read interface of the activity logs (data_and_sync.md §6).

public import Foundation

/// Reads the blocks of the block log and the open block, the tracker state,
/// and the settings, with the exclusions of the current `settings.toml`
/// applied to every read.
public protocol ActivityReading: Sendable {
    // `nil` devices means every device, which an empty set cannot express.
    // swiftlint:disable discouraged_optional_collection
    /// The foreground blocks overlapping `interval` by start, the open block
    /// included; `devices` keeps each block's part on those device names.
    func blocks(in interval: DateInterval, devices: Set<String>?) async throws -> [ActivityBlock]
    /// The background blocks overlapping `interval` by start; `devices`
    /// keeps the items on those device names.
    func backgroundBlocks(in interval: DateInterval, devices: Set<String>?) async throws -> [ActivityBlock]
    // swiftlint:enable discouraged_optional_collection
    /// The parsed `current.json`; `nil` off the Mac or without one.
    func currentState() async -> TrackerState?
    /// The current `settings.toml`, the defaults without one.
    var settings: TrackerSettings { get }
    /// The exclusions of `settings`, with `~` resolved.
    var exclusions: ExclusionRules { get }
    /// Changes of the block log, `current.json`, and `settings.toml`.
    var changes: AsyncStream<ActivityChange> { get }
}

extension ActivityReading {
    /// The foreground blocks of every device overlapping `interval`.
    public func blocks(in interval: DateInterval) async throws -> [ActivityBlock] {
        try await blocks(in: interval, devices: nil)
    }
}

extension ActivityBlock {
    /// Whether the block overlaps `interval`; an empty block counts when it lies inside.
    func overlaps(_ interval: DateInterval) -> Bool {
        end > start ? start < interval.end && end > interval.start : interval.contains(start)
    }
}
