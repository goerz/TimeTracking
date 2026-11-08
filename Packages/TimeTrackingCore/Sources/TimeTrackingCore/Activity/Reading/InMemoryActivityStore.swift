// InMemoryActivityStore: an ActivityReading over blocks in memory, for
// tests, `-UITesting`, and devices without a log (data_and_sync.md §6).

public import Foundation
import Synchronization

/// Foreground and background blocks and a tracker state held in memory.
/// Exclusions and the device filter apply as in the file-backed reader.
public final class InMemoryActivityStore: ActivityReading {
    private struct State {
        var blocks: [ActivityBlock] = []
        var trackerState: TrackerState?
        var settings = TrackerSettings.defaults
    }

    private let state = Mutex(State())
    private let broadcaster = Broadcaster<ActivityChange>()
    private let homeDirectory: String

    /// A store holding `blocks` (foreground and background) and `trackerState`.
    public init(
        blocks: [ActivityBlock] = [],
        trackerState: TrackerState? = nil,
        settings: TrackerSettings = .defaults,
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.homeDirectory = homeDirectory
        state.withLock { state in
            state.blocks = blocks
            state.trackerState = trackerState
            state.settings = settings
        }
    }

    // MARK: Mutation (tests and fixtures)

    /// Adds blocks, replacing those with the same id, and yields a change per date.
    public func append(_ blocks: [ActivityBlock]) {
        state.withLock { state in
            let ids = Set(blocks.map(\.id))
            state.blocks = state.blocks.filter { !ids.contains($0.id) } + blocks
        }
        yieldChanges(of: blocks)
    }

    /// Removes blocks by id.
    public func remove(_ ids: Set<ActivityBlock.ID>) {
        let removed = state.withLock { state in
            let removed = state.blocks.filter { ids.contains($0.id) }
            state.blocks.removeAll { ids.contains($0.id) }
            return removed
        }
        yieldChanges(of: removed)
    }

    /// Replaces the tracker state and yields a change.
    public func setTrackerState(_ trackerState: TrackerState?) {
        state.withLock { $0.trackerState = trackerState }
        broadcaster.yield(.currentState)
    }

    /// Replaces the settings and yields a change.
    public func setSettings(_ settings: TrackerSettings) {
        state.withLock { $0.settings = settings }
        broadcaster.yield(.settings)
    }

    private func yieldChanges(of blocks: [ActivityBlock]) {
        for day in Set(blocks.map(\.day)).sorted() {
            broadcaster.yield(.blocks(day: day))
        }
    }

    // MARK: ActivityReading

    // `nil` means every device, unlike an empty set.
    // swiftlint:disable discouraged_optional_collection
    public func blocks(in interval: DateInterval, devices: Set<String>?) -> [ActivityBlock] {
        var result = stored(in: interval, devices: devices).filter { !$0.isBackgroundBlock }
        if let open = currentState()?.block, !result.contains(where: { $0.start < open.end && $0.end > open.start }),
           open.overlaps(interval),
           let block = open.part(on: devices).flatMap(exclusions.applied(to:))
        {
            result.append(block)
        }
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func backgroundBlocks(in interval: DateInterval, devices: Set<String>?) -> [ActivityBlock] {
        stored(in: interval, devices: devices).filter(\.isBackgroundBlock)
    }

    private func stored(in interval: DateInterval, devices: Set<String>?) -> [ActivityBlock] {
        let rules = exclusions
        return state.withLock(\.blocks)
            .filter { $0.overlaps(interval) }
            .compactMap { $0.part(on: devices).flatMap(rules.applied(to:)) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    // swiftlint:enable discouraged_optional_collection

    public func currentState() -> TrackerState? {
        state.withLock(\.trackerState)
    }

    public var settings: TrackerSettings {
        state.withLock(\.settings)
    }

    public var exclusions: ExclusionRules {
        settings.exclusions(homeDirectory: homeDirectory)
    }

    public var changes: AsyncStream<ActivityChange> {
        broadcaster.stream()
    }
}
