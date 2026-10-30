// projects, clients, areas, and the project, area, and client writes
// (spec_automation.md §3.8, §3.9). There is no command to delete them.

import ArgumentParser
import Foundation
import TimeTrackingCore

struct AreaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "area",
        abstract: "Create, rename, or recolor an area.",
        subcommands: [Create.self, Rename.self, SetColor.self]
    )

    static func changed(_ verb: String, _ summary: AreaSummary, context: ToolContext) {
        let place = summary.client.map { "\($0.name) / " } ?? ""
        context.changed("\(verb) area \(place)\(summary.area.name) \(summary.area.color.uppercased()).") {
            AutomationRecords.area(summary)
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create an area; the default color unless --color."
        )
        @Argument var name: String
        @Option(help: ArgumentHelp("The client.", valueName: "name")) var client: String
        @Option(help: ArgumentHelp("#RRGGBB.", valueName: "color")) var color: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: true)
            try await AreaCommand.changed("Created", service.createArea(name, client: client, color: color), context: context)
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename an area.")
        @Argument var old: String
        @Argument var new: String
        @Option(help: ArgumentHelp("The client.", valueName: "name")) var client: String
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            let (context, service) = try await ToolContext.open(global, writing: true)
            try await AreaCommand.changed("Renamed", service.renameArea(old, to: new, client: client), context: context)
        }
    }

    struct SetColor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set-color", abstract: "Recolor an area.")
        @Argument var name: String
        @Option(help: ArgumentHelp("#RRGGBB.", valueName: "color")) var color: String
        @Option(help: ArgumentHelp("The client.", valueName: "name")) var client: String?
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            _ = try AutomationService.color(color)
            let (context, service) = try await ToolContext.open(global, writing: true)
            try await AreaCommand.changed("Recolored", service.setAreaColor(name, color: color, client: client), context: context)
        }
    }
}
