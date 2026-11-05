// Import and export for the tool (automation.md §3.10, §8.2).

public import Foundation

extension AutomationService {
    /// Which CSV table `export --format csv` writes.
    public enum CSVTable: String, Sendable, CaseIterable {
        case entries
        case projects
        case areas
        case clients
    }

    /// Imports the product's JSON export; validation failures are exit 7
    /// and write nothing. A dry run imports into an in-memory copy, so the
    /// store may be opened read-only and its file stays untouched.
    public func importDocument(_ data: Data, dryRun: Bool, includeSettings: Bool) async throws(AutomationError) -> ImportReport {
        let store = store
        let options = ImportOptions(includeSettings: includeSettings, defaultTimeZone: timeZone.identifier)
        return try await run {
            let target = dryRun ? try await store.inMemoryCopy() : store
            return try await target.importDocument(data, options: options)
        }
    }

    /// The JSON export (`data_and_sync.md` §5.1).
    public func exportDocument(includeDeleted: Bool) async throws(AutomationError) -> Data {
        let store = store
        return try await run {
            try await store.exportDocument(includeDeleted: includeDeleted)
        }
    }

    /// One CSV table; entries of `range` (all time when `nil`).
    public func exportCSV(_ table: CSVTable, range: DayRange?) async throws(AutomationError) -> String {
        let store = store
        let zone = timeZone
        switch table {
        case .entries:
            let result = try await entries(in: range)
            return ReportCSVWriter.entriesCSV(result.listings, now: result.now, timeZone: zone)
        case .projects:
            return try await ReportCSVWriter.projectsCSV(projects(state: .all), timeZone: zone)
        case .areas:
            return try await run {
                try await ReportCSVWriter.areasCSV(store.areas(of: nil, includeRetired: true), clients: store.clients(includeRetired: true))
            }
        case .clients:
            return try await run { try await ReportCSVWriter.clientsCSV(store.clients(includeRetired: true)) }
        }
    }
}
