// ActivityBlock+Hours: a block's time spread over the local hours it covers
// (activity.md §1.4; data_and_sync.md §6).

import Foundation

extension ActivityBlock {
    /// `total` (the active time by default) per local hour, in proportion
    /// to the overlap, in whole seconds that add up to the total (largest
    /// remainder): 09:40 to 10:20 puts half into 9 and half into 10.
    public func hourShares(total: Int? = nil) -> [Int: Int] {
        let local = LocalTimestamp(date: start, utcOffset: utcOffset)
        let start = local.secondOfDay
        let span = max(0, Int(end.timeIntervalSince(self.start).rounded()))
        let total = total ?? activeSeconds
        guard span > 0 else {
            return [local.hour: total]
        }
        let end = start + span
        var parts: [HourPart] = []
        var hour = start / 3600
        while hour * 3600 < end {
            let overlap = min(end, (hour + 1) * 3600) - max(start, hour * 3600)
            let numerator = total * overlap
            parts.append(HourPart(hour: hour % 24, seconds: numerator / span, remainder: numerator % span))
            hour += 1
        }
        var leftover = total - parts.reduce(0) { $0 + $1.seconds }
        let byRemainder = parts.indices.sorted { lhs, rhs in
            parts[lhs].remainder == parts[rhs].remainder ? lhs < rhs : parts[lhs].remainder > parts[rhs].remainder
        }
        for index in byRemainder where leftover > 0 {
            parts[index].seconds += 1
            leftover -= 1
        }
        return parts.reduce(into: [:]) { $0[$1.hour, default: 0] += $1.seconds }
    }

    /// The fraction of the block's span in each local hour.
    public var hourFractions: [Int: Double] {
        let start = LocalTimestamp(date: start, utcOffset: utcOffset).secondOfDay
        let span = end.timeIntervalSince(self.start)
        guard span > 0 else {
            return [start / 3600: 1]
        }
        let end = Double(start) + span
        var result: [Int: Double] = [:]
        var hour = start / 3600
        while Double(hour * 3600) < end {
            let overlap = min(end, Double((hour + 1) * 3600)) - max(Double(start), Double(hour * 3600))
            result[hour % 24, default: 0] += overlap / span
            hour += 1
        }
        return result
    }
}

private struct HourPart {
    var hour: Int
    var seconds: Int
    var remainder: Int
}
