// ActivityBars+Target: what a pointer points at in the bar chart, and what
// the chart says about it (spec_activity.md §1.5, §3).

extension ActivityBars {
    /// A bar or, with `series`, one of its segments.
    public struct Target: Sendable, Hashable {
        public var bar: Bar.ID
        public var series: Series?

        public init(bar: Bar.ID, series: Series? = nil) {
            self.bar = bar
            self.series = series
        }
    }

    public func bar(of target: Target) -> Bar? {
        bars.first { $0.id == target.bar }
    }

    /// What hovering `target` shows: the segment's line, or the bar's total
    /// with its largest contexts; `nil` for a bar still in the future.
    public func tooltip(of target: Target, displayName: (String) -> String) -> String? {
        guard let bar = bar(of: target), !bar.isFuture else {
            return nil
        }
        return target.series.map { bar.tooltip(for: $0, displayName: displayName) } ?? bar.summaryTooltip(displayName: displayName)
    }
}

extension ActivityBars.Series {
    /// The layer's name, with `displayName` for a context.
    public func title(displayName: (String) -> String) -> String {
        if case let .context(context) = self {
            return displayName(context)
        }
        return title
    }
}

extension ActivityBars.Bar {
    /// The layer of the stack at `seconds` above the axis; `nil` outside the stack.
    public func series(atSeconds seconds: Double) -> ActivityBars.Series? {
        guard seconds >= 0 else {
            return nil
        }
        var top = 0
        for segment in segments {
            top += segment.seconds
            if seconds < Double(top) {
                return segment.series
            }
        }
        return nil
    }

    /// "Thu Oct 29 · paper · 4h 12m of 6h 38m".
    public func tooltip(for series: ActivityBars.Series, displayName: (String) -> String) -> String {
        let part = segments.first { $0.series == series }?.seconds ?? 0
        let name = series.title(displayName: displayName)
        return "\(title) · \(name) · \(ActivityText.duration(part)) of \(ActivityText.duration(seconds))"
    }

    /// "Thu Oct 29 · 6h 38m · paper 4h 12m, Mail 1h 10m, Safari 20m": the
    /// total and the three largest contexts.
    public func summaryTooltip(displayName: (String) -> String) -> String {
        let largest = segments
            .compactMap { segment -> (name: String, seconds: Int)? in
                guard case let .context(context) = segment.series else {
                    return nil
                }
                return (displayName(context), segment.seconds)
            }
            .sorted { ($1.seconds, $0.name) < ($0.seconds, $1.name) }
            .prefix(3)
            .map { "\($0.name) \(ActivityText.duration($0.seconds))" }
        let total = "\(title) · \(ActivityText.duration(seconds))"
        return largest.isEmpty ? total : "\(total) · \(largest.joined(separator: ", "))"
    }
}
