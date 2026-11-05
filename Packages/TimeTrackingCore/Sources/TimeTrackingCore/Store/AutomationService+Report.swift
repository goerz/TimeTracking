// The tool's report and the name filters of entries and report
// (automation.md §3.6, §3.7).

import Foundation

extension AutomationService {
    /// The entry filter of `--project`, `--client`, `--area`, `--task`, and
    /// `--no-project`; names resolve as everywhere (archived projects too,
    /// since a filter only reads).
    public func filter(
        project: String? = nil,
        client: String? = nil,
        area: String? = nil,
        task: String? = nil,
        noProject: Bool = false
    ) async throws(AutomationError) -> EntryFilter {
        let store = store
        var filter = EntryFilter(taskContains: task, noProjectOnly: noProject)
        if let project {
            filter.projects = try await [store.resolveProject(project, client: client, includeArchived: true).project.id]
        } else if let client {
            filter.clients = try await [store.resolveClient(client).id]
        }
        if let area {
            filter.areas = try await [store.resolveArea(area, client: project == nil ? client : nil).id]
        }
        if noProject, project != nil || client != nil || area != nil {
            throw .usage("--no-project cannot be combined with --project, --client, or --area.")
        }
        return filter
    }

    /// The report the tool prints: the library's report query over `range`
    /// (cut at its instant bounds), with health time only when `includeHealth`.
    public func report(
        range: DayRange,
        groupBy: [GroupKey],
        granularity: Granularity,
        filter: EntryFilter = EntryFilter(),
        includeHealth: Bool = false
    ) async throws(AutomationError) -> ReportResult {
        guard (1 ... 4).contains(groupBy.count), Set(groupBy).count == groupBy.count else {
            throw .usage("--group-by takes one to four distinct keys of client, area, project, task, day.")
        }
        guard let days = range.days else {
            throw .usage("The range is empty.")
        }
        var query = ReportQuery(days: days, groupBy: groupBy, granularity: granularity, filter: filter)
        query.bounds = range.bounds(in: calendar)
        query.includeHealth = includeHealth
        let store = store
        let root = try await run { try await store.report(query) }
        return ReportResult(
            range: range,
            query: query,
            root: root,
            periods: calendar.periods(granularity, covering: days),
            timeZone: calendar.timeZone
        )
    }
}

/// A report with its range and periods.
public struct ReportResult: Hashable, Sendable {
    public var range: DayRange
    public var query: ReportQuery
    public var root: ReportNode
    /// Every period of the range, empty and future ones included.
    public var periods: [TrackingPeriod]
    /// The zone of the instants `from` and `to` echo.
    public var timeZone: TimeZone

    /// One row per leaf group and period with a non-zero duration, period
    /// by period.
    public var rows: [Row] {
        let paths = root.leafPaths
        return periods.flatMap { period in
            paths.compactMap { path -> Row? in
                guard let leaf = path.last, let seconds = leaf.buckets[period], seconds > 0 else {
                    return nil
                }
                return Row(period: period, path: path, seconds: seconds, entries: leaf.entryBuckets[period] ?? 0)
            }
        }
    }

    /// One row of the report table.
    public struct Row: Hashable, Sendable {
        public var period: TrackingPeriod
        /// The nodes from the first level to the leaf.
        public var path: [ReportNode]
        public var seconds: Int
        public var entries: Int
    }

    /// The seconds of `period` over all groups.
    public func seconds(in period: TrackingPeriod) -> Int {
        root.buckets[period] ?? 0
    }

    /// The JSON of section 3.7.
    public var json: JSONValue {
        let groupBy = query.groupBy
        return .object([
            "from": .string(range.fromText(in: timeZone)),
            "to": .string(range.toText(in: timeZone)),
            "granularity": .string(query.granularity.rawValue),
            "groupBy": .array(groupBy.map { .string($0.rawValue) }),
            "rows": .array(rows.map { row in
                var members = [JSONValue.Member("period", .string(row.period.description))]
                for (key, node) in zip(groupBy, row.path) {
                    members.append(JSONValue.Member(key.rawValue, .optional(node.name)))
                }
                members.append(JSONValue.Member("duration", .int(row.seconds)))
                members.append(JSONValue.Member("entries", .int(row.entries)))
                return .object(members)
            }),
            "periods": .array(periods.map { period in
                .object(["period": .string(period.description), "duration": .int(seconds(in: period))])
            }),
            "total": .int(root.seconds),
        ])
    }

    /// The Breakdown CSV of section 8.2: a `period` column first unless the
    /// granularity is `total`.
    public var csv: String {
        ReportCSVWriter.breakdownCSV(root, levels: query.groupBy, periods: query.granularity == .total ? [] : periods)
    }
}
