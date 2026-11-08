// TrackerHealth: the health record of current.json (activity_tracking.md §3.5, §4.4).

public import Foundation

/// The health record: the last tick, the agent version, and every source.
public struct TrackerHealth: Sendable, Hashable {
    public var lastTick: Date
    public var version: String
    public var sources: [TrackerSourceHealth]

    public init(lastTick: Date, version: String, sources: [TrackerSourceHealth]) {
        self.lastTick = lastTick
        self.version = version
        self.sources = sources
    }
}
