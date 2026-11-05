// SyncStatus: what the sync engine is doing (data_and_sync.md §3.1).

import Foundation

/// The state shown by the sync indicator.
public enum SyncStatus: Hashable, Sendable {
    case idle
    case sending(Int)
    case fetching
    case waitingForNetwork
    case noAccount
    case error(String)
}
