// Building a ReportSnapshot from one scan of the matching entries
// (spec_reports.md §4, §5, §6; spec_data_and_sync.md §7.3).

import Foundation
import GRDB

extension TimeStore {
    /// Tiles, chart, breakdown, and entry list of `request`.
    public func reportSnapshot(_ request: ReportRequest) throws -> ReportSnapshot {
        let query = request.query
        let rows = try reportRows(query)
        let tree = Self.tree(of: rows, query: query)
        let steps = try projectSteps()
        let clientOrder = try clients(includeRetired: true).map(\.id)
        let summary = Self.summary(of: rows, days: request.days, today: request.today)
        let granularity = request.granularity ?? .automatic(dayCount: request.days.lowerBound.distance(to: request.days.upperBound) + 1)
        let keys = StackKeyBuilder(kind: request.stack, steps: steps, clientOrder: clientOrder)
        var chart = Self.chart(of: rows, request: request, granularity: granularity, keys: keys)
        if granularity == .day {
            chart.averageLine = summary.averagePerDay
        }
        let entries = try request.includeEntries ? entryList(query: query, levels: request.levels, path: request.entryPath) : nil
        return ReportSnapshot(
            request: request,
            summary: summary,
            chart: chart,
            tree: tree,
            entries: entries ?? ReportEntryList(listings: [], stoppedSeconds: 0),
            projectSteps: steps,
            now: clock.now
        )
    }

    /// The matching entries whose keys at `levels` equal `path`.
    func entryList(query: ReportQuery, levels: [GroupKey], path: [GroupKeyValue]) throws -> ReportEntryList {
        let projects = try reportProjects()
        let now = clock.now
        let calendar = displayCalendar(timeZone: timeZone())
        let reach = calendar.reach(of: query.days)
        let matching = try entries(
            matching: query,
            where: "e.start < ? AND COALESCE(e.\"end\", ?) > ?",
            [Time.seconds(reach.end), Time.seconds(now), Time.seconds(reach.start)]
        )
        let listings = try listings(for: matching)
            .flatMap { $0.pieces(in: calendar, at: now) }
            .filter { listing in
                let entry = listing.entry
                let project = entry.projectID.flatMap { projects[$0.rawValue] }
                return query.days.contains(entry.day) && zip(levels, path).allSatisfy { level, value in
                    switch level {
                    case .client: value == .client(project?.clientID)
                    case .area: value == .area(project?.areaID)
                    case .project: value == .project(entry.projectID)
                    case .task: value == .task(entry.task.trimmed)
                    case .day: value == .day(entry.day)
                    }
                }
            }
            .anchoringEditors()
        let stopped = listings.reduce(0) { $0 + ($1.entry.isRunning ? 0 : $1.entry.seconds(at: now)) }
        return ReportEntryList(listings: listings, stoppedSeconds: stopped)
    }

    /// The day of the earliest live entry (All time's first day).
    public func earliestEntryDay() throws -> TrackingDay? {
        let first = try fetchEntries(where: "deleted_at IS NULL", [], order: "start, id LIMIT 1").first
        return first.map { displayCalendar(timeZone: timeZone()).displayDay(of: $0) }
    }

    /// Each live project's position within its area, by folded name.
    func projectSteps() throws -> [ProjectID: Int] {
        let rows = try read { database in
            try Row.fetchAll(database, sql: "SELECT id, area_id, name FROM project WHERE deleted_at IS NULL")
        }
        let projects = rows.compactMap { row -> StepProject? in
            guard let id = ProjectID(row["id"] as String) else {
                return nil
            }
            return StepProject(id: id, area: row["area_id"], name: (row["name"] as String).folded)
        }
        var steps: [ProjectID: Int] = [:]
        for group in Dictionary(grouping: projects, by: \.area).values {
            for (index, project) in group.sorted(by: { ($0.name, $0.id) < ($1.name, $1.id) }).enumerated() {
                steps[project.id] = index
            }
        }
        return steps
    }

    static func summary(of rows: [ReportRow], days: ClosedRange<TrackingDay>, today: TrackingDay) -> ReportSummary {
        var perDay: [TrackingDay: Int] = [:]
        for row in rows {
            perDay[row.day, default: 0] += row.seconds
        }
        let elapsed = today < days.lowerBound ? 0 : days.lowerBound.distance(to: min(today, days.upperBound)) + 1
        return ReportSummary(
            loggedSeconds: rows.reduce(0) { $0 + $1.seconds },
            entryCount: rows.reduce(0) { $0 + $1.count },
            includesRunning: rows.contains(where: \.running),
            daysWithEntries: perDay.values.count { $0 > 0 },
            elapsedDays: elapsed
        )
    }

    static func chart(of rows: [ReportRow], request: ReportRequest, granularity: Granularity, keys: StackKeyBuilder) -> ReportChart {
        let range = request.days
        var sums: [TrackingDay: [GroupKeyValue: Int]] = [:]
        var known: [GroupKeyValue: StackKey] = [:]
        var order: [GroupKeyValue: String] = [:]
        var periodStarts: [TrackingDay: TrackingDay] = [:]
        for row in rows {
            let key = keys.value(of: row)
            if known[key] == nil {
                known[key] = keys.key(for: row)
                order[key] = keys.sortKey(of: row)
            }
            let day = row.day
            let start = periodStarts[day] ?? TrackingPeriod(granularity, containing: day).start
            periodStarts[day] = start
            sums[start, default: [:]][key, default: 0] += row.seconds
        }
        let legendKeys = known.keys.sorted { (order[$0] ?? "", "\($0)") < (order[$1] ?? "", "\($1)") }
        let periods = TrackingCalendar(timeZone: .gmt).periods(granularity, covering: range)
        let buckets = periods.map { period in
            let values = sums[period.start] ?? [:]
            let segments = legendKeys.compactMap { key -> StackSegment? in
                guard let seconds = values[key], seconds > 0, let stackKey = known[key] else {
                    return nil
                }
                return StackSegment(key: stackKey, seconds: seconds)
            }
            return bucket(period, range: range, today: request.today, segments: segments)
        }
        let tallest = buckets.map(\.total).max() ?? 0
        return ReportChart(
            granularity: granularity,
            buckets: buckets,
            legend: request.stack == .unstacked ? [] : legendKeys.compactMap { known[$0] },
            axisHours: max(1, (tallest + 3599) / 3600),
            averageLine: nil,
            labelStride: max(1, (buckets.count + 30) / 31)
        )
    }

    static func bucket(
        _ period: TrackingPeriod,
        range: ClosedRange<TrackingDay>,
        today: TrackingDay,
        segments: [StackSegment]
    ) -> ChartBucket {
        let end = period.nextStart.map { $0.adding(days: -1) } ?? range.upperBound
        let days = max(period.start, range.lowerBound) ... min(end, range.upperBound)
        let partial = days != period.start ... end && period.granularity != .day
        let count = days.lowerBound.distance(to: days.upperBound) + 1
        let past = today < days.lowerBound ? 0 : days.lowerBound.distance(to: min(today, days.upperBound)) + 1
        let first = days.lowerBound
        let spanText = DayText.span(days, withYear: false)
        let (label, title): ([String], String) = switch period.granularity {
        case .day, .total:
            ([DayText.shortWeekday(first), DayText.monthSlashDay(first)], DayText.longWeekdayDate(first))
        case .week:
            (["W\(period.start.isoWeek.week)", spanText], "Week \(period.start.isoWeek.week) · \(spanText)")
        case .month:
            (
                [DayText.shortMonth(first), partial ? spanText : String(first.year)],
                partial ? DayText.span(days, withYear: true) : DayText.monthYear(first)
            )
        case .year:
            (
                partial ? [String(first.year), spanText] : [String(first.year)],
                partial ? DayText.span(days, withYear: true) : String(first.year)
            )
        }
        let note = partial ? "partial \(period.granularity.rawValue) (\(count) \(count == 1 ? "day" : "days"))" : nil
        return ChartBucket(
            period: period,
            days: days,
            isPartial: partial,
            isFuture: days.lowerBound > today,
            segments: segments,
            total: segments.reduce(0) { $0 + $1.seconds },
            pastDayCount: past,
            label: label,
            title: title,
            partialNote: note
        )
    }
}

/// A project for the lightness steps.
private struct StepProject {
    var id: ProjectID
    var area: String
    var name: String
}

/// Stack keys, colors, and order of the chart (spec_reports.md §4.4).
struct StackKeyBuilder {
    var kind: StackKind
    var steps: [ProjectID: Int]
    /// Live clients alphabetically (the client palette order).
    var clientOrder: [ClientID]

    private static let last = "\u{10FFFF}"

    func value(of row: ReportRow) -> GroupKeyValue {
        switch kind {
        case .unstacked: .total
        case .client: .client(row.clientID)
        case .area: .area(row.areaID)
        case .project: .project(row.projectID)
        }
    }

    func key(for row: ReportRow) -> StackKey {
        let value = value(of: row)
        switch kind {
        case .unstacked:
            return StackKey(value: value, name: "Logged time", color: .accent)
        case .client:
            guard let id = row.clientID else {
                return StackKey(value: value, name: "No client", color: .gray)
            }
            let index = clientOrder.firstIndex(of: id) ?? 0
            return StackKey(value: value, name: row.clientName ?? "", color: .palette(index % 8))
        case .area:
            guard let color = row.areaColor else {
                return StackKey(value: value, name: "No area", color: .gray)
            }
            return StackKey(value: value, name: row.areaName ?? "", color: .area(color, hatched: false))
        case .project:
            guard let project = row.projectID, let color = row.areaColor else {
                return StackKey(value: value, name: "No project", color: .gray)
            }
            let step = steps[project] ?? 0
            let stepped = (try? AreaColor(color).lightnessStep(step).hex) ?? color
            return StackKey(value: value, name: row.projectName ?? "", color: .area(stepped, hatched: AreaColor.isRepeatedStep(step)))
        }
    }

    /// Stack order: alphabetical clients; areas by client name and area
    /// order; projects by area order and name; the "No" keys last.
    func sortKey(of row: ReportRow) -> String {
        switch kind {
        case .unstacked:
            ""
        case .client:
            row.clientID == nil ? Self.last : row.sortKey(.client)
        case .area:
            row.areaID == nil ? Self.last : row.sortKey(.area)
        case .project:
            row.projectID == nil ? Self.last : row.sortKey(.area) + "\u{1E}" + row.sortKey(.project)
        }
    }
}
