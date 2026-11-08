// activity: the tracker's blocks that start in a range, with their totals
// and their coverage by entries (automation.md §3.12).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ActivityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activity",
        abstract: "List the tracker's blocks that start in a range (default today), with their coverage by entries."
    )

    @OptionGroup var range: RangeOptions

    @Flag(name: .customLong("open"), help: "Include the open block of the running tracker.")
    var includeOpen = false

    @Option(help: "foreground or background (default both).")
    var kind: String?

    @Flag(help: "Only foreground blocks with a stretch no entry covers, and only those stretches.")
    var untracked = false

    @Option(
        name: .customLong("min"),
        help: ArgumentHelp("With --untracked, the shortest stretch listed, in minutes (default 10).", valueName: "minutes")
    )
    var minimum: Int?

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        if let kind, ActivityQuery.Kind(rawValue: kind) == nil {
            throw ValidationError("--kind takes foreground or background.")
        }
        if minimum != nil, !untracked {
            throw ValidationError("--min needs --untracked.")
        }
        if let minimum, minimum < 0 {
            throw ValidationError("--min takes a number of minutes.")
        }
        if untracked, kind == "background" {
            throw ValidationError("--untracked lists foreground blocks only.")
        }
    }

    func run() async throws {
        let (context, service) = try await ToolContext.open(global, writing: false)
        let today = DayRange(from: service.today, to: service.today.adding(days: 1))
        let range = try range.resolve(service, default: today) ?? today
        let query = ActivityQuery(
            includeOpen: includeOpen,
            kind: kind.flatMap(ActivityQuery.Kind.init(rawValue:)),
            untrackedMinimum: untracked ? TimeInterval((minimum ?? 10) * 60) : nil
        )
        let listing = try await service.activity(in: range, reader: context.activityReader(), query: query)
        try context.emit(json: { listing.json }, text: { Self.table(listing, untracked: untracked, colors: context.colors) })
    }

    /// One row per block (or per uncovered stretch with `--untracked`),
    /// then a line per date file that could not be read.
    private static func table(_ listing: ActivityListing, untracked: Bool, colors: Bool) -> String {
        let zone = listing.calendar.timeZone
        var lines: [String] = []
        if listing.rows.isEmpty {
            lines.append(untracked ? "No untracked activity." : "No activity.")
        } else if untracked {
            var table = TextTable(headers: ["Date", "Start", "End", "Untracked", "Workspace", "Item"], rightAligned: [3])
            for row in listing.rows {
                for stretch in row.uncovered {
                    table.add([
                        ToolFormat.date(stretch.start, zone), ToolFormat.time(stretch.start, zone), ToolFormat.time(stretch.end, zone),
                        ToolFormat.duration(Int(stretch.duration.rounded())), workspace(row.block), item(row.block),
                    ])
                }
            }
            lines.append(table.render(colors: colors))
        } else {
            var table = TextTable(
                headers: ["Date", "Start", "End", "Active", "Covered", "Ended", "Workspace", "Item"],
                rightAligned: [3, 4]
            )
            for row in listing.rows {
                let block = row.block
                table.add([
                    ToolFormat.date(block.start, zone), ToolFormat.time(block.start, zone),
                    block.isOpen ? "open" : ToolFormat.time(block.end, zone),
                    block.isBackgroundBlock ? "background" : ToolFormat.duration(block.activeSeconds),
                    row.coveredSeconds.map(ToolFormat.duration) ?? "",
                    block.endReason?.rawValue ?? "",
                    workspace(block), item(block),
                ])
            }
            lines.append(table.render(colors: colors))
        }
        lines += listing.fileProblems
        return lines.joined(separator: "\n")
    }

    /// The dominant workspace by name; a background block's by its items.
    private static func workspace(_ block: ActivityBlock) -> String {
        if let dominant = block.dominantWorkspace {
            return ActivityItem.workspaceName(dominant.workspace)
        }
        return block.background.max { $0.seconds < $1.seconds }?.item.workspaceName ?? ""
    }

    private static func item(_ block: ActivityBlock) -> String {
        (block.dominantItem ?? block.background.max { $0.seconds < $1.seconds })?.item.label ?? ""
    }
}
