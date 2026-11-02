// InMemoryActivityStore: an ActivityReading over blocks in memory, for
// tests, `-UITesting`, and devices without a log (spec_data_and_sync.md §6).

public import Foundation
import Synchronization

/// Blocks, details, and a tracker state held in memory. Exclusions are not
/// applied (callers hand in what the reader would return).
public final class InMemoryActivityStore: ActivityReading {
    private struct State {
        var blocks: [ActivityBlock] = []
        var details: [ActivityBlock.ID: ActivityBlockDetail] = [:]
        var trackerState: TrackerState?
        var contexts: [String: String] = [:]
        var exclusions = ExclusionRules()
    }

    private let state = Mutex(State())
    private let broadcaster = Broadcaster<ActivityChange>()

    public init(
        blocks: [ActivityBlock] = [],
        details: [ActivityBlockDetail] = [],
        trackerState: TrackerState? = nil,
        contexts: [String: String] = [:]
    ) {
        state.withLock { state in
            state.blocks = blocks
            state.details = Dictionary(details.map { ($0.blockID, $0) }) { first, _ in first }
            state.trackerState = trackerState
            state.contexts = contexts
        }
    }

    // MARK: Mutation (tests and fixtures)

    /// Adds blocks (replacing those with the same id) and yields a change.
    public func append(_ blocks: [ActivityBlock]) {
        let months = state.withLock { state in
            let ids = Set(blocks.map(\.id))
            state.blocks = state.blocks.filter { !ids.contains($0.id) } + blocks
            return Set(blocks.map(\.month))
        }
        for month in months.sorted() {
            broadcaster.yield(.blocks(month: month))
        }
    }

    /// Removes blocks by id.
    public func remove(_ ids: Set<ActivityBlock.ID>) {
        let months = state.withLock { state in
            let removed = state.blocks.filter { ids.contains($0.id) }
            state.blocks.removeAll { ids.contains($0.id) }
            return Set(removed.map(\.month))
        }
        for month in months.sorted() {
            broadcaster.yield(.blocks(month: month))
        }
    }

    // MARK: ActivityReading

    // swiftlint:disable:next discouraged_optional_collection
    public func blocks(in interval: DateInterval, devices: Set<String>?) -> [ActivityBlock] {
        state.withLock(\.blocks)
            .filter { block in
                block.end > block.start ? block.start < interval.end && block.end > interval.start : interval.contains(block.start)
            }
            .compactMap { FileActivityStore.part(of: $0, on: devices) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func detail(for id: ActivityBlock.ID) -> ActivityBlockDetail? {
        state.withLock { $0.details[id] }
    }

    public func currentState() -> TrackerState? {
        state.withLock(\.trackerState)
    }

    public func aggregate(in interval: DateInterval, by key: ActivityGroupKey, device: String?) -> [ActivityAggregate] {
        ActivityAggregation.aggregate(blocks(in: interval, devices: device.map { [$0] }), by: key)
    }

    public func bundleIdentifier(forContext context: String) -> String? {
        state.withLock { $0.contexts[context] }
    }

    public var exclusions: ExclusionRules {
        state.withLock(\.exclusions)
    }

    public var changes: AsyncStream<ActivityChange> {
        broadcaster.stream()
    }
}
