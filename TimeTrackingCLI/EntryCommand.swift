// entries and entry show|create|edit|delete (spec_automation.md §3.6).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct EntryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "entry",
        abstract: "Show, create, edit, or delete one entry.",
        subcommands: [Show.self, Create.self, Edit.self, Delete.self]
    )

    /// Prints entries as a table, or `{"entries": [...]}`.
    static func emit(_ listings: [EntryListing], service: AutomationService, context: ToolContext) throws(AutomationError) {
        let zone = context.timeZone
        try context.emit(
            json: { AutomationRecords.entryList(listings, now: service.now, timeZone: zone) },
            csv: { ReportCSVWriter.entriesCSV(listings, now: service.now, timeZone: zone) },
            text: { ToolFormat.entriesTable(listings, now: service.now, zone: zone, colors: context.colors) }
        )
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Print one entry.")

        @Argument(help: "The entry's id.")
        var id: String

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: false)
            let entry = try await service.store.resolveEntry(id)
            try await EntryCommand.emit([service.listing(entry)], service: service, context: context)
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a stopped entry.")

        @Argument(help: "The task.")
        var task: String?

        @Option(help: ArgumentHelp("Start time.", valueName: "time"))
        var start: String

        @Option(help: ArgumentHelp("End time.", valueName: "time"))
        var end: String

        @Option(help: ArgumentHelp("The project.", valueName: "name"))
        var project: String?

        @Option(name: .customLong("project-id"), help: ArgumentHelp("The project's id.", valueName: "uuid"))
        var projectID: String?

        @Option(help: ArgumentHelp("The project's client.", valueName: "name"))
        var client: String?

        @Flag(help: "Allow an overlap.")
        var force = false

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: true)
            let draft = try await EntryDraft(
                projectID: service.project(name: project, id: projectID, client: client)?.project.id,
                task: task ?? "",
                start: service.instant(start),
                end: service.instant(end),
                timeZone: context.timeZone.identifier
            )
            let pieces = try await service.createEntry(draft, force: force)
            try EntryCommand.changed("Created", pieces, service: service, context: context)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "edit", abstract: "Change one entry.")

        @Argument(help: "The entry's id.")
        var id: String

        @Option(help: ArgumentHelp("New start time.", valueName: "time"))
        var start: String?

        @Option(help: ArgumentHelp("New end time.", valueName: "time"))
        var end: String?

        @Option(help: ArgumentHelp("New project.", valueName: "name"))
        var project: String?

        @Option(name: .customLong("project-id"), help: ArgumentHelp("New project's id.", valueName: "uuid"))
        var projectID: String?

        @Option(help: ArgumentHelp("The project's client.", valueName: "name"))
        var client: String?

        @Flag(name: .customLong("no-project"), help: "Remove the project.")
        var noProject = false

        @Option(help: ArgumentHelp("New task.", valueName: "text"))
        var task: String?

        @Flag(help: "Allow an overlap.")
        var force = false

        @OptionGroup var global: GlobalOptions

        func validate() throws {
            if noProject, project != nil || projectID != nil {
                throw ValidationError("--no-project cannot be combined with --project.")
            }
        }

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: true)
            let entry = try await service.store.resolveEntry(id)
            var change = EntryChange(task: task)
            if noProject {
                change.projectID = .some(nil)
            } else if let row = try await service.project(name: project, id: projectID, client: client) {
                change.projectID = .some(row.project.id)
            }
            change.start = try start.map { text throws(AutomationError) in try service.instant(text) }
            change.end = try end.map { text throws(AutomationError) in try service.instant(text) }
            let pieces = try await service.editEntry(entry.id, change, force: force)
            try EntryCommand.changed("Changed", pieces, service: service, context: context)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete one entry; without --yes, print it and exit 2."
        )

        @Argument(help: "The entry's id.")
        var id: String

        @Flag(help: "Really delete.")
        var yes = false

        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: yes)
            let listing = try await service.listing(service.store.resolveEntry(id))
            guard yes else {
                // stdout stays empty on an error: the entry goes to stderr.
                ToolContext.writeError(ToolFormat.entriesTable([listing], now: service.now, zone: context.timeZone, colors: false))
                throw AutomationError.usage("Add --yes to delete this entry.")
            }
            try await service.deleteEntry(listing.entry.id)
            try context.changed("Deleted \(ToolFormat.subject(listing)) of \(ToolFormat.date(listing.entry.start, context.timeZone)).") {
                .object(["deleted": .string(listing.entry.id.rawValue)])
            }
        }
    }

    /// One line per piece, or `{"entries": [...]}`.
    static func changed(
        _ verb: String,
        _ pieces: [EntryListing],
        service: AutomationService,
        context: ToolContext
    ) throws(AutomationError) {
        let zone = context.timeZone
        let lines = pieces.map { piece in
            let entry = piece.entry
            let end = entry.end.map { ToolFormat.time($0, zone) } ?? "now"
            return "\(verb) \(ToolFormat.subject(piece)) on \(ToolFormat.date(entry.start, zone)) "
                + "from \(ToolFormat.time(entry.start, zone)) to \(end) (\(entry.id.rawValue))."
        }
        try context.changed(lines.joined(separator: "\n")) {
            AutomationRecords.entryList(pieces, now: service.now, timeZone: zone)
        }
    }
}
