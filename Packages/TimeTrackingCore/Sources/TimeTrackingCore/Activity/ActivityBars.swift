// ActivityBars: active time by day, week, or month, stacked by context
// (spec_activity.md §1.5).

/// The stacked bar chart.
public struct ActivityBars: Sendable {
    public enum Granularity: Sendable, Hashable {
        case day
        case week
        case month
    }

    /// A stack layer, bottom up in the Contexts ranking.
    public enum Series: Sendable, Hashable {
        case context(String)
        /// Contexts beyond the twelfth.
        case otherContexts
        /// `a` minus item seconds (no filter only).
        case notItemized

        public var title: String {
            switch self {
            case let .context(name): ActivityContext(name).displayName()
            case .otherContexts: "Other apps"
            case .notItemized: "Brief activity"
            }
        }
    }

    public struct Segment: Sendable, Hashable {
        public var series: Series
        public var seconds: Int
    }

    public struct Bar: Sendable, Identifiable {
        public var id: String
        /// "Mon", "29", "W44", or "Oct".
        public var label: String
        /// The weekday initial under a day number (ranges over 7 days).
        public var sublabel: String?
        /// "Thu Oct 29", "W44", "October 2026" (tooltips).
        public var title: String
        public var days: [TrackingDay]
        public var segments: [Segment]
        public var seconds: Int
        /// The open block's part (hatched top).
        public var openSeconds: Int
        public var isToday: Bool
        public var isFuture: Bool

        /// "Thu Oct 29 · paper · 4h 12m of 6h 38m".
        public func tooltip(for series: Series) -> String {
            let part = segments.first { $0.series == series }?.seconds ?? 0
            return "\(title) · \(series.title) · \(ActivityText.duration(part)) of \(ActivityText.duration(seconds))"
        }
    }

    public var granularity: Granularity
    public var series: [Series]
    public var bars: [Bar]
    /// The y axis' top in hours: the tallest bar rounded up to an even hour.
    public var axisHours: Int

    /// The bar granularity of a range.
    public static func granularity(days: [TrackingDay]) -> Granularity {
        if days.count <= 31 {
            return .day
        }
        let weeks = Set(days.map { $0.adding(days: 1 - $0.isoWeekday) }).count
        return weeks <= 53 ? .week : .month
    }
}

extension ActivitySummary {
    /// The stacked bars (§1.5).
    public var bars: ActivityBars {
        let all = Self.days(input.days)
        let granularity = ActivityBars.granularity(days: all)
        let filteredRanking = Self.rank(blocks.flatMap(selectedItems))
        let shown = Set(filteredRanking.prefix(12).map(\.context))
        var series = filteredRanking.prefix(12).map { ActivityBars.Series.context($0.context) }
        if filteredRanking.count > 12 {
            series.append(.otherContexts)
        }
        if input.contexts.isEmpty {
            series.append(.notItemized)
        }
        let groups: [(key: TrackingDay, days: [TrackingDay])] = switch granularity {
        case .day: all.map { ($0, [$0]) }
        case .week: Dictionary(grouping: all) { $0.adding(days: 1 - $0.isoWeekday) }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        case .month: Dictionary(grouping: all) { TrackingDay(year: $0.year, month: $0.month, day: 1) }.sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        }
        let byDay = Dictionary(grouping: blocks) { $0.localDay }
        let bars = groups.map { key, days in
            bar(
                key: key,
                days: days,
                blocks: days.flatMap { byDay[$0.description] ?? [] },
                layout: BarLayout(granularity: granularity, shown: shown, series: series)
            )
        }
        let tallest = bars.map(\.seconds).max() ?? 0
        let hours = (tallest + 3599) / 3600
        return ActivityBars(granularity: granularity, series: series, bars: bars, axisHours: max(2, hours + hours % 2))
    }

    private func bar(
        key: TrackingDay,
        days: [TrackingDay],
        blocks: [ActivityBlock],
        layout: BarLayout
    ) -> ActivityBars.Bar {
        let shown = layout.shown
        var seconds: [ActivityBars.Series: Int] = [:]
        var open = 0
        for block in blocks {
            let items = selectedItems(block)
            for item in items {
                seconds[shown.contains(item.context) ? .context(item.context) : .otherContexts, default: 0] += item.seconds
            }
            if input.contexts.isEmpty {
                seconds[.notItemized, default: 0] += max(0, block.activeSeconds - items.reduce(0) { $0 + $1.seconds })
            }
            if block.isOpen {
                open += value(block)
            }
        }
        let segments = layout.series
            .compactMap { layer in seconds[layer].flatMap { $0 > 0 ? ActivityBars.Segment(series: layer, seconds: $0) : nil } }
        let labels = BarLabels(
            key: key,
            granularity: layout.granularity,
            dayCount: input.days.lowerBound.distance(to: input.days.upperBound) + 1
        )
        return ActivityBars.Bar(
            id: key.description,
            label: labels.label,
            sublabel: labels.sublabel,
            title: labels.title,
            days: days,
            segments: segments,
            seconds: segments.reduce(0) { $0 + $1.seconds },
            openSeconds: open,
            isToday: days.contains(input.today),
            isFuture: days.allSatisfy { $0 > input.today }
        )
    }
}

/// The granularity and stack layers of every bar.
private struct BarLayout {
    var granularity: ActivityBars.Granularity
    var shown: Set<String>
    var series: [ActivityBars.Series]
}

/// A bar's label, sublabel, and tooltip title.
private struct BarLabels {
    var label: String
    var sublabel: String?
    var title: String

    init(key: TrackingDay, granularity: ActivityBars.Granularity, dayCount: Int) {
        switch granularity {
        case .day:
            self.title = "\(DayText.shortWeekday(key)) \(DayText.shortMonth(key)) \(key.day)"
            if dayCount <= 7 {
                self.label = DayText.shortWeekday(key)
            } else {
                self.label = "\(key.day)"
                self.sublabel = String(DayText.shortWeekday(key).prefix(1))
            }
        case .week:
            self.label = "W\(key.isoWeek.week)"
            self.title = label
        case .month:
            self.label = DayText.shortMonth(key)
            self.title = DayText.monthYear(key)
        }
    }
}
