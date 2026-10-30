// importDocument on the store, with dry runs (spec_data_and_sync.md §5.2).

public import Foundation

extension TimeStore {
    /// Imports an export-format document in one transaction followed by the
    /// invariant pass; with `options.dryRun` the transaction is rolled back.
    public func importDocument(_ data: Data, options: ImportOptions = ImportOptions()) throws -> ImportReport {
        do {
            return try write { transaction in
                var report = try transaction.importDocument(data, options: options)
                try transaction.runInvariantPass()
                report.splitPieces = transaction.splitPieceCount
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
private struct DryRun: Error {
    var report: ImportReport
}
