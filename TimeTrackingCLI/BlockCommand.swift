// block list|create|edit|delete: time blocks, the events of the
// time-block calendar (automation.md §3.14; calendar.md §4.1, §4.2).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct BlockCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "block",
        abstract: "List, create, edit, or delete time blocks.",
        subcommands: [List.self, Create.self, Edit.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List the time blocks that start in a range (default today)."
        )

        @OptionGroup var range: RangeOptions

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: false)
            let today = DayRange(from: service.today, to: service.today.adding(days: 1))
            let range = try range.resolve(service, default: today) ?? today
            let listing = try await service.timeBlocks(in: range, context: context.timeBlockContext())
            try context.emit(json: { listing.json }, text: {
                BlockCommand.table(listing.records, zone: context.timeZone, colors: context.colors)
            })
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a time block.")

        @Argument(help: "The title.")
        var title: String

        @Option(parsing: .unconditional, help: ArgumentHelp("Start time.", valueName: "time"))
        var start: String

        @Option(parsing: .unconditional, help: ArgumentHelp("End time.", valueName: "time"))
        var end: String

        @Option(help: ArgumentHelp("The project, linked by its URL.", valueName: "name"))
        var project: String?

        @Option(name: .customLong("project-id"), help: ArgumentHelp("The project's id.", valueName: "uuid"))
        var projectID: String?

        @Option(help: ArgumentHelp("The project's client.", valueName: "name"))
        var client: String?

        @Option(help: ArgumentHelp("The notes.", valueName: "text"))
        var notes: String?

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: false)
            try BlockCommand.rejectCSV(context)
            let record = try await service.createTimeBlock(
                title: title,
                start: service.instant(start),
                end: service.instant(end),
                projectID: service.project(name: project, id: projectID, client: client)?.project.id,
                notes: notes.flatMap { $0.isEmpty ? nil : $0 },
                context: context.timeBlockContext()
            )
            BlockCommand.changed("Created", record, context: context)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "edit", abstract: "Change one time block.")

        @Argument(help: "The block's id, as block list prints it.")
        var id: String

        @Option(help: ArgumentHelp("New title.", valueName: "text"))
        var title: String?

        @Option(parsing: .unconditional, help: ArgumentHelp("New start time.", valueName: "time"))
        var start: String?

        @Option(parsing: .unconditional, help: ArgumentHelp("New end time.", valueName: "time"))
        var end: String?

        @Option(help: ArgumentHelp("New project, linked by its URL.", valueName: "name"))
        var project: String?

        @Option(name: .customLong("project-id"), help: ArgumentHelp("New project's id.", valueName: "uuid"))
        var projectID: String?

        @Option(help: ArgumentHelp("The project's client.", valueName: "name"))
        var client: String?

        @Flag(name: .customLong("no-project"), help: "Remove the project URL.")
        var noProject = false

        @Option(help: ArgumentHelp("New notes; an empty text removes them.", valueName: "text"))
        var notes: String?

        @OptionGroup var global: GlobalOptions

        func validate() throws {
            if noProject, project != nil || projectID != nil {
                throw ValidationError("--no-project cannot be combined with --project.")
            }
        }

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: false)
            try BlockCommand.rejectCSV(context)
            var change = try TimeBlockChange(title: title, start: service.instant(ifGiven: start), end: service.instant(ifGiven: end))
            if noProject {
                change.projectID = .some(nil)
            } else if let row = try await service.project(name: project, id: projectID, client: client) {
                change.projectID = .some(row.project.id)
            }
            if let notes {
                change.notes = .some(notes.isEmpty ? nil : notes)
            }
            let record = try await service.editTimeBlock(id, change, context: context.timeBlockContext())
            BlockCommand.changed("Changed", record, context: context)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete one time block; without --yes, print it and exit 2."
        )

        @Argument(help: "The block's id, as block list prints it.")
        var id: String

        @Flag(help: "Really delete.")
        var yes = false

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: false)
            try BlockCommand.rejectCSV(context)
            let calendar = try context.timeBlockContext()
            guard yes else {
                let record = try await service.timeBlock(id, context: calendar)
                // stdout stays empty on an error: the block goes to stderr.
                ToolContext.writeError(BlockCommand.table([record], zone: context.timeZone, colors: false))
                throw AutomationError.usage("Add --yes to delete this time block.")
            }
            let record = try await service.deleteTimeBlock(id, context: calendar)
            context.changed("Deleted \(BlockCommand.subject(record)) of \(ToolFormat.date(record.block.event.start, context.timeZone)).") {
                .object(["deleted": .string(record.block.id)])
            }
        }
    }

    // MARK: Output

    /// The block commands write the calendar, never the store, which they
    /// open read-only; a write still has no CSV form.
    static func rejectCSV(_ context: ToolContext) throws(AutomationError) {
        if context.options.csv {
            throw .usage("Write commands have no CSV form.")
        }
    }

    /// `"Title" on Project`, or `"Title"`.
    static func subject(_ record: TimeBlockRecord) -> String {
        let title = "\"\(record.block.title)\""
        return record.project.map { "\(title) on \($0.project.name)" } ?? title
    }

    /// One line, or `{"blocks": [record]}`.
    static func changed(_ verb: String, _ record: TimeBlockRecord, context: ToolContext) {
        let zone = context.timeZone
        let event = record.block.event
        let line = "\(verb) \(subject(record)) on \(ToolFormat.date(event.start, zone)) "
            + "from \(ToolFormat.time(event.start, zone)) to \(ToolFormat.time(event.end, zone)) (\(record.block.id))."
        context.changed(line) {
            .object(["blocks": .array([record.json(timeZone: zone)])])
        }
    }

    static func table(_ records: [TimeBlockRecord], zone: TimeZone, colors: Bool) -> String {
        guard !records.isEmpty else {
            return "No time blocks."
        }
        var table = TextTable(headers: ["Date", "Start", "End", "Title", "Project", "Client", "Id"])
        for record in records {
            let event = record.block.event
            table.add([
                ToolFormat.date(event.start, zone), ToolFormat.time(event.start, zone), ToolFormat.time(event.end, zone),
                event.title, record.project?.project.name ?? record.unlinkedReason.map { "(\($0))" } ?? "",
                record.project?.client?.name ?? "", record.block.id,
            ])
        }
        return table.render(colors: colors)
    }
}
