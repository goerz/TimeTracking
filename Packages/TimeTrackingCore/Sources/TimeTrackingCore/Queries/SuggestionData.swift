// SuggestionData: the store side of the Calendar's suggestion engine (spec_data_and_sync.md §7.3).

public import Foundation
import GRDB

/// What the suggestion engine reads from the store and the activity log.
public protocol SuggestionData: Sendable {
    /// For each block, the entries overlapping it by at least `minOverlap` seconds.
    func entriesOverlapping(_ blocks: [ActivityBlock], minOverlap: TimeInterval) async throws
        -> [(ActivityBlock, [(TimeEntry, overlapSeconds: Int)])]
    func activityDuring(_ entry: TimeEntry) async throws -> [ActivityBlock]
    /// Newest first.
    func feedback(in interval: DateInterval) async throws -> [SuggestionFeedback]
}

/// `SuggestionData` over a store and an activity reader.
public struct StoreSuggestionData: SuggestionData {
    public let store: TimeStore
    public let activity: any ActivityReading

    public init(store: TimeStore, activity: any ActivityReading) {
        self.store = store
        self.activity = activity
    }

    public func entriesOverlapping(_ blocks: [ActivityBlock], minOverlap: TimeInterval) async throws
        -> [(ActivityBlock, [(TimeEntry, overlapSeconds: Int)])] {
        guard let first = blocks.map(\.start).min(), let last = blocks.map(\.end).max() else {
            return []
        }
        let now = store.clock.now
        let entries = try await store.entries(in: DateInterval(start: first, end: max(first, last)), includeDeleted: false)
        return blocks.map { block in
            let matches = entries.compactMap { entry -> (TimeEntry, overlapSeconds: Int)? in
                let overlap = min(block.end, entry.end ?? now).timeIntervalSince(max(block.start, entry.start))
                return overlap >= max(minOverlap, 1) ? (entry, Int(overlap)) : nil
            }
            return (block, matches)
        }
    }

    public func activityDuring(_ entry: TimeEntry) async throws -> [ActivityBlock] {
        try await activity.blocks(in: entry.interval(at: store.clock.now), devices: nil)
    }

    public func feedback(in interval: DateInterval) async throws -> [SuggestionFeedback] {
        try await store.feedback(in: interval)
    }
}

extension TimeStore {
    /// Suggestion feedback recorded in `interval`, newest first.
    public func feedback(in interval: DateInterval) throws -> [SuggestionFeedback] {
        try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT * FROM suggestion_feedback WHERE deleted_at IS NULL AND recorded_at >= ? AND recorded_at < ?
                ORDER BY recorded_at DESC, id
                """,
                arguments: [Time.seconds(interval.start), Time.seconds(interval.end)]
            ).map(SuggestionFeedback.init(row:))
        }
    }
}
