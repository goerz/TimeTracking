// TransactionOutcome: what a committed write transaction changed, and the
// store error for a SQLite error (spec_data_and_sync.md §2.2, §7.4).

import GRDB

/// What a committed transaction changed.
struct TransactionOutcome: Sendable {
    var changedEntryIDs: Set<EntryID>
    var changedSettings: Set<String>
    var structureChanged: Bool
    var liveStateChanged: Bool
    var adjustments: [EntryAdjustment]
    var queuedCount: Int
    var splitPieces: Int

    init(_ transaction: StoreTransaction) {
        self.changedEntryIDs = transaction.changedEntryIDs
        self.changedSettings = transaction.changedSettings
        self.structureChanged = transaction.structureChanged
        self.liveStateChanged = transaction.liveStateChanged
        self.adjustments = transaction.adjustments
        self.queuedCount = transaction.queued.count
        self.splitPieces = transaction.splitPieceCount
    }

    var hasChanges: Bool {
        queuedCount > 0 || !changedEntryIDs.isEmpty || structureChanged || liveStateChanged || !changedSettings.isEmpty
    }
}

extension StoreError {
    /// The store error for a SQLite error: `busy` for a lock held past the
    /// busy timeout, `database` otherwise.
    init(_ error: DatabaseError) {
        switch error.resultCode {
        case .SQLITE_BUSY, .SQLITE_LOCKED:
            self = .busy
        default:
            self = .database(String(describing: error))
        }
    }
}
