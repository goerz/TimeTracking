// ActivityReading: the read interface of the activity logs (spec_data_and_sync.md §6).

public import Foundation

/// Reads blocks, details, the tracker state, and aggregates.
public protocol ActivityReading: Sendable {
    // `nil` devices means every device, which an empty set cannot express.
    // swiftlint:disable discouraged_optional_collection
    /// The blocks overlapping `interval` by start, exclusions applied;
    /// `devices` limits them to those device names.
    func blocks(in interval: DateInterval, devices: Set<String>?) async throws -> [ActivityBlock]
    // swiftlint:enable discouraged_optional_collection
    /// URLs, files, and presence of a block; `nil` off the recording Mac.
    func detail(for id: ActivityBlock.ID) async throws -> ActivityBlockDetail?
    /// The parsed `current.json`, Mac only.
    func currentState() async -> TrackerState?
    /// Seconds per context, subject, group key, hour of day, or day.
    func aggregate(in interval: DateInterval, by key: ActivityGroupKey, device: String?) async throws -> [ActivityAggregate]
    /// The bundle identifier (or process name) the headers give for `context`.
    func bundleIdentifier(forContext context: String) -> String?
    /// The exclusions of the current `settings.toml`.
    var exclusions: ExclusionRules { get }
    /// Changes of the block log, `current.json`, and `settings.toml`.
    var changes: AsyncStream<ActivityChange> { get }
}

extension ActivityReading {
    /// The blocks of every device overlapping `interval`.
    public func blocks(in interval: DateInterval) async throws -> [ActivityBlock] {
        try await blocks(in: interval, devices: nil)
    }
}
