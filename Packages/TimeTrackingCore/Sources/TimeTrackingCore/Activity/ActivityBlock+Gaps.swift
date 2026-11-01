// ActivityBlock+Gaps: stretches of a day without a block of any device, for
// the Calendar's gap labels (spec_calendar.md §3.1).

public import Foundation

extension ActivityBlock {
    /// The stretches longer than `minimum` that no block covers, across all
    /// devices, in order; `blocks` lie on one local day.
    public static func gaps(between blocks: [ActivityBlock], longerThan minimum: TimeInterval) -> [DateInterval] {
        let sorted = blocks.sorted { $0.start < $1.start }
        guard var covered = sorted.first?.end else {
            return []
        }
        var gaps: [DateInterval] = []
        for block in sorted.dropFirst() {
            if block.start.timeIntervalSince(covered) > minimum {
                gaps.append(DateInterval(start: covered, end: block.start))
            }
            covered = max(covered, block.end)
        }
        return gaps
    }
}
