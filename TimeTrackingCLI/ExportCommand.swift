// check, import, export (automation.md §3.10, §4).

import ArgumentParser
import Foundation
import TimeTrackingCore

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Write the JSON export, or with --format csv the Entries CSV or a structure table."
    )

    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: ArgumentHelp("A file (a folder for --what all); default stdout.", valueName: "path")
    )
    var output: String?

    @Flag(name: .customLong("include-deleted"), help: "Include tombstones (JSON only).")
    var includeDeleted = false

    @Option(help: "json (default) or csv.")
    var format = "json"

    @Option(help: "entries (default), projects, areas, clients, or all; with --format csv.")
    var what: String?

    @OptionGroup var range: RangeOptions

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        guard ["json", "csv"].contains(format) else {
            throw ValidationError("--format takes json or csv.")
        }
        if format == "json", what != nil || !range.isEmpty {
            throw ValidationError("A range or --what needs --format csv.")
        }
        if let what, what != "all", AutomationService.CSVTable(rawValue: what) == nil {
            throw ValidationError("--what takes entries, projects, areas, clients, or all.")
        }
        if what == "all", output == nil {
            throw ValidationError("--what all needs -o naming a folder.")
        }
    }

    func run() async throws {
        let (_, service) = try await ToolContext.open(global, writing: false)
        guard format == "csv" else {
            let data = try await service.exportDocument(includeDeleted: includeDeleted)
            try write(data, to: output)
            return
        }
        let range = try range.resolve(service, default: nil)
        if what == "all", let output {
            let folder = URL(filePath: output, directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw AutomationError.failure("Cannot create \(output).")
            }
            for table in AutomationService.CSVTable.allCases {
                let text = try await service.exportCSV(table, range: range)
                try write(Data(text.utf8), to: folder.appending(path: "\(table.rawValue).csv").path)
            }
            return
        }
        let table = AutomationService.CSVTable(rawValue: what ?? "entries") ?? .entries
        try await write(Data(service.exportCSV(table, range: range).utf8), to: output)
    }

    private func write(_ data: Data, to path: String?) throws(AutomationError) {
        guard let path else {
            FileHandle.standardOutput.write(data)
            if data.last != UInt8(ascii: "\n") {
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            return
        }
        do {
            try data.write(to: URL(filePath: path), options: .atomic)
        } catch {
            throw .failure("Cannot write \(path).")
        }
    }
}
