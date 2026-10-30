// GlobalOptions: the options every subcommand accepts (spec_automation.md §3.1).

import ArgumentParser
import Foundation

/// `--json`, `--csv`, `--store`, `--quiet`, `--no-color`.
struct GlobalOptions: ParsableArguments {
    @Flag(help: "JSON output.")
    var json = false

    @Flag(help: "CSV output.")
    var csv = false

    @Option(help: ArgumentHelp("Use this store file (default: the live store; also TIMETRACKING_STORE).", valueName: "path"))
    var store: String?

    @Flag(name: [.customLong("quiet"), .customShort("q")], help: "No output on success for write commands.")
    var quiet = false

    @Flag(name: .customLong("no-color"), help: "No ANSI color.")
    var noColor = false

    func validate() throws {
        if json, csv {
            throw ValidationError("--json and --csv are mutually exclusive.")
        }
    }

    /// The global options that may stand before the subcommand, and
    /// whether each takes a value.
    static let names: [String: Bool] = [
        "--json": false, "--csv": false, "--quiet": false, "-q": false, "--no-color": false, "--store": true,
    ]
}
