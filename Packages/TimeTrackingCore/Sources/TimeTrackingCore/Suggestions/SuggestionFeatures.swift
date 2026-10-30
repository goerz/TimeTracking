// SuggestionFeatures: what an example or a query looks like to the model
// (spec_planner_calendar.md §5.1, §5.3).

public import Foundation

/// The features of a stretch of time: activity, calendar title, time, and
/// the previous project.
public struct SuggestionFeatures: Sendable, Hashable, Codable {
    /// Group key → weighted seconds.
    public var groupKeys: [String: Double]
    /// Token → weighted seconds (`c:`, `s:`, `d:`, `g:`).
    public var tokens: [String: Double]
    public var contexts: Set<String>
    /// `k:` tokens of a covering event or time block.
    public var titleTokens: Set<String>
    /// Start hour and weekday as (sine, cosine).
    public var hour: [Double]
    public var weekday: [Double]
    public var isWeekend: Bool
    public var minutes: Double
    /// The previous entry's project that day; `previousKnown` false means unknown.
    public var previousProject: ProjectID?
    public var previousKnown: Bool
    public var start: Date

    /// Features from items weighted by seconds.
    public init(
        items: [ActivityItem],
        groupKeys: [String: Double],
        title: String?,
        interval: DateInterval,
        previousProject: ProjectID?,
        previousKnown: Bool,
        timeZone: TimeZone
    ) {
        var tokens: [String: Double] = [:]
        var contexts = Set<String>()
        for item in items where item.seconds > 0 {
            contexts.insert(item.context)
            for token in SuggestionTokens.tokens(of: item) {
                tokens[token, default: 0] += Double(item.seconds)
            }
        }
        for (key, seconds) in groupKeys where seconds > 0 {
            tokens[SuggestionTokens.groupToken(key), default: 0] += seconds
        }
        self.groupKeys = groupKeys.filter { $0.value > 0 }
        self.tokens = tokens
        self.contexts = contexts
        self.titleTokens = SuggestionTokens.titleTokens(title)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: interval.start)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        let weekday = Double(((parts.weekday ?? 1) + 5) % 7)
        self.hour = [sin(2 * .pi * hour / 24), cos(2 * .pi * hour / 24)]
        self.weekday = [sin(2 * .pi * weekday / 7), cos(2 * .pi * weekday / 7)]
        self.isWeekend = weekday >= 5
        self.minutes = interval.duration / 60
        self.previousProject = previousProject
        self.previousKnown = previousKnown
        self.start = interval.start
    }

    /// The items and group keys of `blocks` during `interval`, each block
    /// weighted by the share of it the interval overlaps (§5.1).
    public static func activity(
        of blocks: [ActivityBlock],
        during interval: DateInterval
    ) -> (items: [ActivityItem], groupKeys: [String: Double]) {
        var items: [ActivityItem] = []
        var groupKeys: [String: Double] = [:]
        for block in blocks {
            let span = block.end.timeIntervalSince(block.start)
            let overlap = interval.overlapDuration(start: block.start, end: block.end)
            guard span > 0, overlap > 0 else {
                continue
            }
            let share = min(1, overlap / span)
            items += block.items.map { item in
                var item = item
                item.seconds = Int((Double(item.seconds) * share).rounded())
                return item
            }
            groupKeys[block.groupKey, default: 0] += Double(block.activeSeconds) * share
        }
        return (items, groupKeys)
    }
}

/// The cyclic distance of two (sine, cosine) pairs, 0 to 1.
func cyclicDistance(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == 2, rhs.count == 2 else {
        return 1
    }
    return ((lhs[0] - rhs[0]) * (lhs[0] - rhs[0]) + (lhs[1] - rhs[1]) * (lhs[1] - rhs[1])).squareRoot() / 2
}

/// 1 − Jaccard; both empty is 0, one empty is 1.
func jaccardDistance(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
    if lhs.isEmpty, rhs.isEmpty {
        return 0
    }
    let union = lhs.union(rhs).count
    return 1 - Double(lhs.intersection(rhs).count) / Double(union)
}

/// 1 − weighted Jaccard of two normalized vectors; 0.5 when either is empty.
func weightedJaccardDistance(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else {
        return 0.5
    }
    var minimum = 0.0
    var maximum = 0.0
    for (key, value) in lhs {
        let other = rhs[key] ?? 0
        minimum += min(value, other)
        maximum += max(value, other)
    }
    for (key, value) in rhs where lhs[key] == nil {
        maximum += value
    }
    return maximum > 0 ? 1 - minimum / maximum : 0.5
}
