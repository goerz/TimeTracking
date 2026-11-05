// importDocument on the store, with dry runs (data_and_sync.md §5.2).

public import Foundation
import GRDB

extension TimeStore {
    /// Imports an export-format document in one transaction followed by the
    /// invariant pass; with `options.dryRun` the transaction is rolled back.
    public func importDocument(_ data: Data, options: ImportOptions = ImportOptions()) throws -> ImportReport {
        do {
            return try write { transaction in
                var report = try transaction.importDocument(data, options: options)
                try transaction.runInvariantPass()
                report.adjustments = transaction.adjustments
                if options.dryRun {
                    throw DryRun(report: report)
                }
                return report
            }
        } catch let dryRun as DryRun {
            return dryRun.report
        }
    }
}

/// Thrown to roll back a dry-run import.
extension TimeStore {
    /// An in-memory copy of this store's database (SQLite's backup), so a
    /// dry run leaves the file untouched; GRDB's write setup alone would
    /// change a WAL file's header.
    public func inMemoryCopy() throws -> TimeStore {
        let copy = try TimeStore(Configuration(location: .inMemory, clock: clock, deviceID: deviceID, timeZone: timeZone))
        guard let target = copy.writer else {
            throw StoreError.readOnly
        }
        do {
            try reader.backup(to: target)
        } catch let error as DatabaseError {
            throw StoreError(error)
        }
        return copy
    }
}

private struct DryRun: Error {
    var report: ImportReport
}
