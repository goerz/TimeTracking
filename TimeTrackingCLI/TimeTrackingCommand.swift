// TimeTrackingCommand: the `timetracking` tool's root command, argument
// order, and exit codes (automation.md §3.1, §3.4, §3.11).

import ArgumentParser
import Darwin
import Foundation
import TimeTrackingCore

@main
struct TimeTrackingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "timetracking",
        abstract: "Read and change tracked time.",
        version: versionString,
        subcommands: [
            StatusCommand.self, StartCommand.self, StopCommand.self, ContinueCommand.self,
            EntriesCommand.self, EntryCommand.self, ReportCommand.self, HealthCommand.self,
            ProjectsCommand.self, ClientsCommand.self, AreasCommand.self,
            ProjectCommand.self, AreaCommand.self, ClientCommand.self,
            CheckCommand.self, ImportCommand.self, ExportCommand.self,
            ActivityCommand.self, TrackerCommand.self, BlockCommand.self,
        ]
    )

    @Flag(name: .customLong("store-path"), help: "Print the resolved store path and exit.")
    var storePath = false

    @OptionGroup var global: GlobalOptions

    /// The tool's version, which equals the app's (the tool ships inside
    /// it), and the store schema version.
    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build)), schema \(TimeStore.schemaVersion)"
    }

    func run() throws {
        guard storePath else {
            throw CleanExit.helpRequest(self)
        }
        let context = ToolContext(global)
        guard let url = context.storeURL else {
            throw AutomationError.storeUnavailable("No store: the App Group container is unavailable.")
        }
        context.write(url.path)
    }

    /// Parses, runs, and exits with the codes of §3.11; errors go to stderr.
    static func main() async {
        let arguments = Self.reordered(Array(CommandLine.arguments.dropFirst()))
        let json = arguments.contains("--json")
        do {
            var command = try parseAsRoot(arguments)
            if var command = command as? AsyncParsableCommand {
                try await command.run()
            } else {
                try command.run()
            }
            Darwin.exit(0)
        } catch let error as AutomationError {
            ToolContext.report(error, json: json)
            Darwin.exit(error.exitCode)
        } catch {
            let code = exitCode(for: error)
            if code == .success {
                ToolContext.write(fullMessage(for: error))
                Darwin.exit(0)
            }
            if let code = error as? ExitCode {
                Darwin.exit(code.rawValue)
            }
            let message = message(for: error).split(separator: "\n").first.map(String.init) ?? "failed"
            let text = message.hasPrefix("Error: ") ? String(message.dropFirst(7)) : message
            let failure: AutomationError = code == .validationFailure ? .usage(text) : .failure(text)
            ToolContext.report(failure, json: json)
            Darwin.exit(failure.exitCode)
        }
    }

    /// Moves the global options given before the subcommand behind it, so
    /// `timetracking --json status` parses like `timetracking status --json`.
    static func reordered(_ arguments: [String]) -> [String] {
        var leading: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let name = String(argument.split(separator: "=", maxSplits: 1).first ?? "")
            guard let takesValue = GlobalOptions.names[name] else {
                break
            }
            leading.append(argument)
            if takesValue, !argument.contains("="), index + 1 < arguments.count {
                leading.append(arguments[index + 1])
                index += 1
            }
            index += 1
        }
        guard index < arguments.count, !arguments[index].hasPrefix("-") else {
            return arguments
        }
        var rest = Array(arguments[index...])
        // After the subcommand path (one or two words), before its arguments.
        var insertion = 1
        if rest.count > 1, ["entry", "project", "area", "client", "block"].contains(rest[0]), !rest[1].hasPrefix("-") {
            insertion = 2
        }
        rest.insert(contentsOf: leading, at: insertion)
        return rest
    }
}
