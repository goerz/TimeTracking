// ChangePoints: where the credited time of a block moves to another
// workspace, and how different the two sides are (activity_tracking.md §2.7).

import Foundation

/// A place where a block could split.
struct ChangePoint: Hashable {
    /// The index of the first credit after the point.
    var index: Int
    /// The point's time, the start of that credit.
    var time: Date
    /// 1 − Σ min(L, R) / Σ max(L, R) over the workspaces' shares before (L)
    /// and after (R): 0 is the same mix, 1 no workspace in common.
    var distance: Double
}

enum ChangePoints {
    /// Every point between `credits` (in time order) where the workspace
    /// changes, with at least `minHalf` of credited time on each side.
    static func find(in credits: [Credit], minHalf: TimeInterval) -> [ChangePoint] {
        guard credits.count > 1 else {
            return []
        }
        let total = credits.reduce(into: [String: Int]()) { $0[$1.item.workspace, default: 0] += $1.seconds }
        let totalSeconds = total.values.reduce(0, +)
        var before: [String: Int] = [:]
        var beforeSeconds = 0
        var points: [ChangePoint] = []
        for index in credits.indices.dropFirst() {
            let previous = credits[index - 1]
            before[previous.item.workspace, default: 0] += previous.seconds
            beforeSeconds += previous.seconds
            guard previous.item.workspace != credits[index].item.workspace,
                  Double(beforeSeconds) >= minHalf, Double(totalSeconds - beforeSeconds) >= minHalf
            else {
                continue
            }
            let after = total.merging(before) { $0 - $1 }
            points.append(ChangePoint(
                index: index,
                time: credits[index].start,
                distance: distance(before, beforeSeconds, after, totalSeconds - beforeSeconds)
            ))
        }
        return points
    }

    /// The point with the largest distance, the earliest on a tie.
    static func best(_ points: [ChangePoint]) -> ChangePoint? {
        points.reduce(nil) { best, point in
            guard let best else {
                return point
            }
            return point.distance > best.distance ? point : best
        }
    }

    private static func distance(_ left: [String: Int], _ leftSeconds: Int, _ right: [String: Int], _ rightSeconds: Int) -> Double {
        var minimum = 0.0
        var maximum = 0.0
        for workspace in Set(left.keys).union(right.keys) {
            let lhs = Double(left[workspace] ?? 0) / Double(max(leftSeconds, 1))
            let rhs = Double(right[workspace] ?? 0) / Double(max(rightSeconds, 1))
            minimum += min(lhs, rhs)
            maximum += max(lhs, rhs)
        }
        return maximum == 0 ? 0 : 1 - minimum / maximum
    }
}
