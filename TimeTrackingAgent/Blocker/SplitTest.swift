// SplitTest: where an open block splits (activity_tracking.md §2.6).

import Foundation

/// The candidate split points of a block are its group-key change points:
/// the start of every segment whose group key differs from the previous
/// segment's. A candidate needs `min_half` of credited time on each side;
/// its distance is the weighted Jaccard distance between the two sides'
/// time-weighted distributions over group keys.
nonisolated enum SplitTest {
    struct Candidate: Hashable {
        /// The index of the first segment after the split.
        var index: Int
        var distance: Double
    }

    /// The candidate with the largest distance (the earliest on a tie), or
    /// `nil` without one. With `after`, only change points at or after it count.
    static func best(in segments: [Blocker.Segment], minHalf: TimeInterval, after: Date? = nil) -> Candidate? {
        guard segments.count > 1 else {
            return nil
        }
        let total = segments.reduce(0) { $0 + $1.seconds }
        var left: [String: Int] = [:]
        var right: [String: Int] = [:]
        for segment in segments {
            right[segment.item.groupKey, default: 0] += segment.seconds
        }
        var leftSeconds = 0
        var best: Candidate?
        for index in 1 ..< segments.count {
            let previous = segments[index - 1]
            left[previous.item.groupKey, default: 0] += previous.seconds
            right[previous.item.groupKey, default: 0] -= previous.seconds
            leftSeconds += previous.seconds
            guard segments[index].item.groupKey != previous.item.groupKey,
                  Double(leftSeconds) >= minHalf, Double(total - leftSeconds) >= minHalf,
                  after.map({ segments[index].start >= $0 }) ?? true
            else {
                continue
            }
            let value = distance(left, leftSeconds, right, total - leftSeconds)
            if best.map({ value > $0.distance }) ?? true {
                best = Candidate(index: index, distance: value)
            }
        }
        return best
    }

    /// `1 - Σ min(p, q) / Σ max(p, q)` over the shares of each key.
    static func distance(_ left: [String: Int], _ leftTotal: Int, _ right: [String: Int], _ rightTotal: Int) -> Double {
        guard leftTotal > 0, rightTotal > 0 else {
            return 0
        }
        var smaller = 0.0
        var larger = 0.0
        for key in Set(left.keys).union(right.keys) {
            let first = Double(left[key] ?? 0) / Double(leftTotal)
            let second = Double(right[key] ?? 0) / Double(rightTotal)
            smaller += min(first, second)
            larger += max(first, second)
        }
        return larger > 0 ? 1 - smaller / larger : 0
    }
}
