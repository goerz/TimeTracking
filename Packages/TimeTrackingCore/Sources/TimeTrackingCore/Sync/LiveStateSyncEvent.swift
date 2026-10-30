// LiveStateSyncEvent: what the sync engine reports about LiveState, for the
// widget pushes (spec_data_and_sync.md §4.3).

import Foundation

/// A `LiveState` the engine confirmed or applied.
public enum LiveStateSyncEvent: Hashable, Sendable {
    /// The server confirmed this device's save.
    case saved(LiveState)
    /// A fetched record was applied; `runningChanged` when its running part
    /// changed the local row.
    case fetched(LiveState, runningChanged: Bool)
}
