// TrackerBlockSettings: the [blocks] table of settings.toml
// (activity_tracking.md §2.7, §2.8, §7.1). A missing key takes its default.

public import Foundation

/// `[blocks]`: when blocks split and close, and how they are summarized.
public struct TrackerBlockSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case splitAfter = "split_after"
        case minHalf = "min_half"
        case minBlock = "min_block"
        case splitThreshold = "split_threshold"
        case idleClose = "idle_close"
        case maxBlock = "max_block"
        case maxPassiveBlock = "max_passive_block"
        case maxBackgroundBlock = "max_background_block"
        case minBackgroundItem = "min_background_item"
        case summaryLines = "summary_lines"
        case summaryMinShare = "summary_min_share"
    }

    public var splitAfter: TimeInterval = 1200
    public var minHalf: TimeInterval = 600
    /// A shorter block is held, then merged into the previous one or dropped (§2.7).
    public var minBlock: TimeInterval = 600
    public var splitThreshold = 0.7
    public var idleClose: TimeInterval = 300
    public var maxBlock: TimeInterval = 5400
    public var maxPassiveBlock: TimeInterval = 3 * 3600
    public var maxBackgroundBlock: TimeInterval = 3 * 3600
    /// A background block keeps only items with at least this much time.
    public var minBackgroundItem: TimeInterval = 300
    public var summaryLines = 6
    public var summaryMinShare = 0.05

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.splitAfter = try container.duration(.splitAfter, default: fallback.splitAfter)
        self.minHalf = try container.duration(.minHalf, default: fallback.minHalf)
        self.minBlock = try container.duration(.minBlock, default: fallback.minBlock)
        self.splitThreshold = try container.number(.splitThreshold, default: fallback.splitThreshold)
        self.idleClose = try container.duration(.idleClose, default: fallback.idleClose)
        self.maxBlock = try container.duration(.maxBlock, default: fallback.maxBlock)
        self.maxPassiveBlock = try container.duration(.maxPassiveBlock, default: fallback.maxPassiveBlock)
        self.maxBackgroundBlock = try container.duration(.maxBackgroundBlock, default: fallback.maxBackgroundBlock)
        self.minBackgroundItem = try container.duration(.minBackgroundItem, default: fallback.minBackgroundItem)
        self.summaryLines = try container.value(.summaryLines, default: fallback.summaryLines)
        self.summaryMinShare = try container.number(.summaryMinShare, default: fallback.summaryMinShare)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(TrackerDuration.format(splitAfter), forKey: .splitAfter)
        try container.encode(TrackerDuration.format(minHalf), forKey: .minHalf)
        try container.encode(TrackerDuration.format(minBlock), forKey: .minBlock)
        try container.encode(splitThreshold, forKey: .splitThreshold)
        try container.encode(TrackerDuration.format(idleClose), forKey: .idleClose)
        try container.encode(TrackerDuration.format(maxBlock), forKey: .maxBlock)
        try container.encode(TrackerDuration.format(maxPassiveBlock), forKey: .maxPassiveBlock)
        try container.encode(TrackerDuration.format(maxBackgroundBlock), forKey: .maxBackgroundBlock)
        try container.encode(TrackerDuration.format(minBackgroundItem), forKey: .minBackgroundItem)
        try container.encode(summaryLines, forKey: .summaryLines)
        try container.encode(summaryMinShare, forKey: .summaryMinShare)
    }
}
