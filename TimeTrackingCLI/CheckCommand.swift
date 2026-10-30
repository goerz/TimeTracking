// check, import, export (spec_automation.md §3.10, §4).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct CheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Compare the store with a description file; --fix repairs what loses nothing."
    )

    @Argument(help: "The description file (TOML or JSON).")
    var file: String

    @Option(help: ArgumentHelp("Only this client.", valueName: "name"))
    var client: String?

    @Flag(help: "Create, recolor, un-retire, and unarchive what the file lists.")
    var fix = false

    @OptionGroup var global: GlobalOptions

    private static let noCSV = "check has no CSV form."

    func run() async throws {
        let description = try DescriptionFile(contentsOf: URL(filePath: file))
        let context = ToolContext(global)
        let service = try await context.service(writing: fix, csvMessage: Self.noCSV)
        let result = try await fix ? service.fix(description, client: client) : service.check(description, client: client)
        if global.csv {
            throw AutomationError.usage(Self.noCSV)
        }
        if global.json {
            context.write(result.json(fixed: fix).text())
        } else {
            let lines = result.actions.map(\.message) + result.inconsistencies.map(\.message)
            if !lines.isEmpty {
                context.write(lines.joined(separator: "\n"))
            }
        }
        if !result.inconsistencies.isEmpty {
            throw ExitCode(AutomationError.inconsistent.exitCode)
        }
    }
}
