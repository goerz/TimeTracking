// report (spec_automation.md §3.7).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Totals by group and period (default the current week)."
    )

    @OptionGroup var range: RangeOptions
    @OptionGroup var filter: FilterOptions

    @Option(name: .customLong("group-by"), help: ArgumentHelp("Up to four of client, area, project, task, day.", valueName: "keys"))
    var groupBy = "client,area,project"

    @Option(help: "total, day, week, or month.")
    var granularity = "total"

    @Flag(help: "Decimal hours instead of h:mm:ss.")
    var hours = false

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let keys = try groupBy.split(separator: ",").map { key throws(AutomationError) in
            guard let key = GroupKey(rawValue: key.trimmingCharacters(in: .whitespaces)) else {
                throw .usage("Unknown --group-by key \"\(key)\"; use client, area, project, task, day.")
            }
            return key
        }
        guard let granularity = Granularity(rawValue: granularity), granularity != .year else {
            throw AutomationError.usage("--granularity takes total, day, week, or month.")
        }
        let (context, service) = try await ToolContext.open(global, writing: false)
        let week = DayRange(TrackingPeriod(.week, containing: service.today))
        guard let range = try range.resolve(service, default: week) else {
            throw AutomationError.usage("A report needs a range; --all-time alone is not one.")
        }
        let result = try await service.report(range: range, groupBy: keys, granularity: granularity, filter: filter.filter(service))
        try context.emit(json: { result.json }, csv: { result.csv }, text: { table(result, colors: context.colors) })
    }

    /// One row per group, one column per period, a Total column, a totals row.
    private func table(_ result: ReportResult, colors: Bool) -> String {
        let hours = hours
        let format: @Sendable (Int) -> String = { hours ? ToolFormat.hours($0) : ToolFormat.duration($0) }
        let periods: [TrackingPeriod] = result.query.granularity == .total ? [] : result.periods
        let levels = result.query.groupBy.map(\.rawValue.capitalized)
        var table = TextTable(headers: levels + periods.map(\.description) + ["Total"])
        table.rightAligned = Set(levels.count ..< levels.count + periods.count + 1)
        for path in result.root.leafPaths {
            guard let leaf = path.last, leaf.seconds > 0 else {
                continue
            }
            let names = path.map { $0.name ?? "(no project)" }
            table.add(names + periods.map { format(leaf.buckets[$0] ?? 0) } + [format(leaf.seconds)])
        }
        table.rule()
        table.add(["Total"] + Array(repeating: "", count: max(0, levels.count - 1)) + periods.map { format(result.seconds(in: $0)) }
            + [format(result.root.seconds)])
        return table.render(colors: colors)
    }
}
