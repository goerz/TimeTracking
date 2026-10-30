// projects, clients, areas, and the project, area, and client writes
// (spec_automation.md §3.8, §3.9). There is no command to delete them.

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Create, archive, unarchive, rename, or move a project.",
        subcommands: [Create.self, Archive.self, Unarchive.self, Rename.self, Move.self]
    )

    static func changed(_ verb: String, _ row: ProjectRow, service _: AutomationService, context: ToolContext) throws(AutomationError) {
        let place = [row.client?.name, row.area?.name].compactMap(\.self).joined(separator: " / ")
        try context.changed("\(verb) project \(row.project.name) in \(place).") {
            AutomationRecords.project(row, timeZone: context.timeZone)
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an active project.")
        @Argument var name: String
        @Option(help: ArgumentHelp("The area.", valueName: "name")) var area: String
        @Option(help: ArgumentHelp("The area's client.", valueName: "name")) var client: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: true)
            try await ProjectCommand.changed(
                "Created",
                service.createProject(name, area: area, client: client),
                service: service,
                context: context
            )
        }
    }

    struct Archive: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "archive", abstract: "Archive a project; entries keep it.")
        @Argument var name: String
        @Option(help: ArgumentHelp("The project's client.", valueName: "name")) var client: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: true)
            try await ProjectCommand.changed("Archived", service.archiveProject(name, client: client), service: service, context: context)
        }
    }

    struct Unarchive: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "unarchive", abstract: "Restore an archived project.")
        @Argument var name: String
        @Option(help: ArgumentHelp("The project's client.", valueName: "name")) var client: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: true)
            try await ProjectCommand.changed(
                "Unarchived",
                service.unarchiveProject(name, client: client),
                service: service,
                context: context
            )
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename a project.")
        @Argument var old: String
        @Argument var new: String
        @Option(help: ArgumentHelp("The project's client.", valueName: "name")) var client: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: true)
            try await ProjectCommand.changed(
                "Renamed",
                service.renameProject(old, to: new, client: client),
                service: service,
                context: context
            )
        }
    }

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move", abstract: "Move a project to an area of any client.")
        @Argument var name: String
        @Option(help: ArgumentHelp("The target area.", valueName: "name")) var area: String
        @Option(help: ArgumentHelp("The target area's client.", valueName: "name")) var client: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let context = ToolContext(global)
            let service = try await context.service(writing: true)
            try await ProjectCommand.changed(
                "Moved",
                service.moveProject(name, toArea: area, client: client),
                service: service,
                context: context
            )
        }
    }
}
