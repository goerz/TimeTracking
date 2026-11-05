// AutomationService+Tool: the time and project arguments of the write
// commands (automation.md §3.2, §3.3).

import Foundation
import TimeTrackingCore

nonisolated extension AutomationService {
    /// Parses a time argument (`--at`, `--start`, `--end`).
    func instant(_ text: String) throws(AutomationError) -> Date {
        try DateArgument.parse(text, now: now, calendar: calendar).instant(in: calendar)
    }

    /// Parses an optional time argument; `nil` when it was not given.
    func instant(ifGiven text: String?) throws(AutomationError) -> Date? {
        try text.map { text throws(AutomationError) in try instant(text) }
    }

    /// The project of `--project NAME` / `--project-id ID` with `--client`.
    func project(name: String?, id: String?, client: String?) async throws(AutomationError) -> ProjectRow? {
        if let id {
            guard name == nil else {
                throw .usage("Give --project or --project-id, not both.")
            }
            return try await store.resolveProject(id: id)
        }
        guard let name else {
            return nil
        }
        return try await store.resolveProject(name, client: client)
    }
}
