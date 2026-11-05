// ActivityBlockDetail+Including: the detail of a block with a short block
// merged into it (activity_tracking.md §2.6, §4.3).

import Foundation
import TimeTrackingCore

nonisolated extension ActivityBlockDetail {
    /// This detail plus the URLs, files, presence transitions, and dwell
    /// times of `earlier` (the replaced block's line) that it lacks, each
    /// list in time order; the items stay this detail's.
    func including(_ earlier: ActivityBlockDetail) -> ActivityBlockDetail {
        func union<Element: Hashable>(_ first: [Element], _ second: [Element], by time: (Element) -> Date) -> [Element] {
            var seen = Set<Element>()
            return (first + second).filter { seen.insert($0).inserted }.sorted { time($0) < time($1) }
        }
        var result = self
        result.urls = union(earlier.urls, urls) { $0.time }
        result.files = union(earlier.files, files) { $0.time }
        result.presence = union(earlier.presence, presence) { $0.time }
        result.dwell = union(earlier.dwell, dwell) { $0.time }
        return result
    }
}
