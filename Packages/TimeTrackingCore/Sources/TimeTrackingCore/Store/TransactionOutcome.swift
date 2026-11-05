// TransactionOutcome: what a committed write transaction changed, and the
// store error for a SQLite error (data_and_sync.md §2.2, §7.4).

import GRDB

/// What a committed transaction changed.
struct TransactionOutcome: Sendable {
    var changedEntryIDs: Set<EntryID>
    var changedSettings: Set<String>
    var structureChanged: Bool
    var liveStateChanged: Bool
    var healthChanged: Bool
    var adjustments: [EntryAdjustment]
    var queuedCount: Int
    var isFromElsewhere: Bool

    init(_ transaction: StoreTransaction) {
        self.changedEntryIDs = transaction.changedEntryIDs
        self.changedSettings = transaction.changedSettings
        self.structureChanged = transaction.structureChanged
        self.liveStateChanged = transaction.liveStateChanged
        self.healthChanged = transaction.healthChanged
        self.adjustments = transaction.adjustments
        self.queuedCount = transaction.queued.count
        self.isFromElsewhere = transaction.isFromElsewhere
    }

    var hasChanges: Bool {
        queuedCount > 0 || !changedEntryIDs.isEmpty || structureChanged || liveStateChanged || healthChanged
            || !changedSettings.isEmpty
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
