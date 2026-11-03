// Blocker+ShortBlocks: holding, merging, and dropping blocks shorter than
// min_block (spec_activity_tracking.md §2.5).

import Foundation
import TimeTrackingCore

nonisolated extension Blocker {
    /// A closed block before its summary.
    struct RawBlock: Hashable, Sendable {
        var start: Date
        var end: Date
        var segments: [Segment]
        var contexts: [String: String]

        var length: TimeInterval {
            end.timeIntervalSince(start)
        }
    }

    /// The time after a short block within which attention continues it,
    /// and before it within which the previous block takes it.
    func mergeWindow(_ short: RawBlock) -> TimeInterval {
        settings.idleClose + short.length
    }

    func isSameDay(_ first: Date, _ second: Date) -> Bool {
        ActivityTimestamp.startOfDay(first, timeZone: timeZone) == ActivityTimestamp.startOfDay(second, timeZone: timeZone)
    }

    /// Whether attention at `time` continues the held block `short`.
    func canContinue(_ short: RawBlock, at time: Date) -> Bool {
        time.timeIntervalSince(short.end) <= mergeWindow(short) && isSameDay(short.start, time)
    }

    /// Merges the held block into the previous block, or drops it.
    mutating func resolveHeld() -> [ClosedBlock] {
        guard let short = held else {
            return []
        }
        held = nil
        guard let before = previous,
              short.start.timeIntervalSince(before.end) <= mergeWindow(short),
              isSameDay(before.start, short.start)
        else {
            return []
        }
        var contexts = before.contexts
        contexts.merge(short.contexts) { first, _ in first }
        let merged = RawBlock(
            start: before.start,
            end: short.end,
            segments: before.segments + short.segments,
            contexts: contexts
        )
        guard merged.length <= lengthLimit(merged.segments) else {
            return []
        }
        previous = merged
        return finish(merged, replacesPrevious: true)
    }

    /// Hands out `raw` as the newest block.
    mutating func emit(_ raw: RawBlock) -> [ClosedBlock] {
        previous = raw
        return finish(raw)
    }

    /// `max_block`, or `max_passive_block` for mostly passive segments.
    func lengthLimit(_ segments: [Segment]) -> TimeInterval {
        let passive = segments.filter(\.passive).reduce(0) { $0 + $1.seconds }
        let total = segments.reduce(0) { $0 + $1.seconds }
        return total > 0 && Double(passive) / Double(total) > 0.5 ? settings.maxPassiveBlock : settings.maxBlock
    }
}
