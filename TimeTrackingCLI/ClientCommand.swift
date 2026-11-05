// projects, clients, areas, and the project, area, and client writes
// (automation.md §3.8, §3.9). There is no command to delete them.

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ClientCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "client",
        abstract: "Create or rename a client.",
        subcommands: [Create.self, Rename.self]
    )

    static func changed(_ verb: String, _ summary: ClientSummary, context: ToolContext) {
        context.changed("\(verb) client \(summary.client.name).") {
            AutomationRecords.client(summary)
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a client with its general area.")
        @Argument var name: String
        @Option(help: ArgumentHelp("The general area's #RRGGBB.", valueName: "color")) var color: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: true)
            try await ClientCommand.changed("Created", service.createClient(name, color: color), context: context)
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename a client and its general area.")
        @Argument var old: String
        @Argument var new: String
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: true)
            try await ClientCommand.changed("Renamed", service.renameClient(old, to: new), context: context)
        }
    }
}
