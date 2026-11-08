// Sample+Times: the times of the Samples that cover an interval of activity
// reported after the fact (activity_tracking.md §2.7 step 2, §6).

import Foundation

extension Sample {
    /// The longest time one Sample covers.
    static let maxCoverage: TimeInterval = 60
    /// The spacing of the Samples placed through an interval.
    static let spacing: TimeInterval = 30

    /// One time every 30 seconds through `interval`, the last 60 seconds
    /// before its end, so the Samples cover it exactly.
    static func times(through interval: DateInterval) -> [Date] {
        guard interval.duration > 0 else {
            return []
        }
        let start = interval.start.timeIntervalSince1970.rounded(.up)
        let last = max(start, (interval.end - maxCoverage).timeIntervalSince1970.rounded(.down))
        var times = Array(stride(from: start, to: last, by: spacing))
        times.append(last)
        return times.map { Date(timeIntervalSince1970: $0) }
    }
}
