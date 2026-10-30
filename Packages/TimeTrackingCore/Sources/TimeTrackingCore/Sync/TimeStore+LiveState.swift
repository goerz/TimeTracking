// The store's LiveState API (spec_data_and_sync.md §4.1, §4.2).

import Foundation

extension TimeStore {
    /// The local `live_state` row (empty before the first write).
    public func liveState() throws -> LiveState {
        try read { database in
            try StoreTransaction(database: database, now: clock.now, deviceID: deviceID, timeZone: timeZone()).liveState()
        }
    }

    /// Writes one Mac's activity entry (`LiveStatePublisher`, Mac app only)
    /// and queues `LiveState`; `nil` removes the entry.
    public func setLiveActivity(_ activity: LiveState.MacActivity?, for device: DeviceID) throws {
        try write { try $0.setLiveActivity(activity, for: device) }
    }
}
