// check, import, export (spec_automation.md §3.10, §4).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import the product's JSON export: upsert by id, never delete."
    )

    @Argument(help: "The JSON export file.")
    var file: String

    @Flag(name: .customLong("dry-run"), help: "Print the summary and write nothing.")
    var dryRun = false

    @Flag(name: .customLong("include-settings"), help: "Apply the synced settings too (restoring a backup).")
    var includeSettings = false

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        guard let data = FileManager.default.contents(atPath: file) else {
            throw AutomationError.failure("Cannot read \(file).")
        }
        let context = ToolContext(global)
        let service = try await context.service(writing: true)
        let report = try await service.importDocument(data, dryRun: dryRun, includeSettings: includeSettings)
        if global.csv {
            throw AutomationError.usage("import has no CSV form.")
        }
        guard !global.quiet else {
            return
        }
        context.write(global.json ? AutomationRecords.importSummary(report).text() : ImportSummary.lines(report).joined(separator: "\n"))
    }
}
