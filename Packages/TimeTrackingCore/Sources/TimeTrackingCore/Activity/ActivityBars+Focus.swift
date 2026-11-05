// ActivityBars+Focus: the arrow keys on the bars and their segments
// (activity.md §2).

extension ActivityBars {
    /// The first bar, whole.
    public var firstTarget: Target? {
        bars.first.map { Target(bar: $0.id) }
    }

    /// What `move` reaches from `target`: left and right the neighboring
    /// bar, keeping the context where that bar has it; up and down the
    /// segments bottom up, and below the lowest the whole bar. An edge stays
    /// put; without a target, or one of a bar no longer shown, the first bar.
    public func target(_ move: ActivityFocusMove, from target: Target?) -> Target? {
        guard let target, let index = bars.firstIndex(where: { $0.id == target.bar }) else {
            return firstTarget
        }
        let bar = bars[index]
        let position = bar.segments.firstIndex { $0.series == target.series }
        switch move {
        case .left, .right:
            let next = bars[min(max(index + (move == .left ? -1 : 1), 0), bars.count - 1)]
            let keeps = next.segments.contains { $0.series == target.series }
            return Target(bar: next.id, series: keeps ? target.series : nil)
        case .above:
            let above = position.map { $0 + 1 } ?? 0
            return bar.segments.indices.contains(above) ? Target(bar: bar.id, series: bar.segments[above].series) : target
        case .below:
            guard let position, position > 0 else {
                return Target(bar: bar.id)
            }
            return Target(bar: bar.id, series: bar.segments[position - 1].series)
        }
    }
}
