// ActivityAggregation: grouping blocks into aggregates (spec_data_and_sync.md §6).

import Foundation

/// The aggregation behind `ActivityReading.aggregate(in:by:device:)`.
///
/// Context and subject buckets sum item seconds; group key and day buckets
/// sum active seconds; hour buckets spread a block's active seconds over
/// the local hours it covers in proportion to the overlap, in whole
/// seconds that add up to the block's total. Value buckets come largest
/// first, hours and days in order.
enum ActivityAggregation {
    static func aggregate(_ blocks: [ActivityBlock], by key: ActivityGroupKey) -> [ActivityAggregate] {
        var seconds: [ActivityAggregate.Bucket: Int] = [:]
        var counts: [ActivityAggregate.Bucket: Int] = [:]
        for block in blocks {
            for (bucket, value) in shares(of: block, by: key) {
                seconds[bucket, default: 0] += value
                counts[bucket, default: 0] += 1
            }
        }
        let rows = seconds.map { ActivityAggregate(bucket: $0.key, seconds: $0.value, blockCount: counts[$0.key] ?? 0) }
        switch key {
        case .context, .subject, .groupKey:
            return rows.sorted { ($1.seconds, $0.bucket) < ($0.seconds, $1.bucket) }
        case .hourOfDay, .day:
            return rows.sorted { $0.bucket < $1.bucket }
        }
    }

    /// The seconds `block` contributes to each bucket of `key`.
    private static func shares(of block: ActivityBlock, by key: ActivityGroupKey) -> [ActivityAggregate.Bucket: Int] {
        switch key {
        case .context:
            block.items.reduce(into: [:]) { $0[.value($1.context), default: 0] += $1.seconds }
        case .subject:
            block.items.reduce(into: [:]) { $0[.value($1.subject), default: 0] += $1.seconds }
        case .groupKey:
            [.value(block.groupKey): block.activeSeconds]
        case .hourOfDay:
            hourShares(of: block).reduce(into: [:]) { $0[.hour($1.key), default: 0] += $1.value }
        case .day:
            [.day(block.localDay): block.activeSeconds]
        }
    }

    /// The active seconds of `block` (or `total`) per local hour, by the
    /// largest remainder method so the parts add up to the total.
    static func hourShares(of block: ActivityBlock, total: Int? = nil) -> [Int: Int] {
        let local = LocalTimestamp(date: block.start, utcOffset: block.utcOffset)
        let start = local.secondOfDay
        let span = max(0, Int(block.end.timeIntervalSince(block.start).rounded()))
        let total = total ?? block.activeSeconds
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
}

private struct HourPart {
    var hour: Int
    var seconds: Int
    var remainder: Int
}

extension ActivityAggregation {
    /// The fraction of `block`'s span in each local hour.
    static func hourFractions(of block: ActivityBlock) -> [Int: Double] {
        let start = LocalTimestamp(date: block.start, utcOffset: block.utcOffset).secondOfDay
        let span = block.end.timeIntervalSince(block.start)
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
