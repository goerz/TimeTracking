// DeviceDay: a device and one of its local dates, the remote activity
// loop's unit of work (activity_tracking.md §2.5).

/// A device and one of its local dates, for the remote loop's pending work.
public struct DeviceDay: Sendable, Hashable, Codable, Comparable {
    public var deviceID: String
    public var day: TrackingDay

    public init(deviceID: String, day: TrackingDay) {
        self.deviceID = deviceID
        self.day = day
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.day, lhs.deviceID) < (rhs.day, rhs.deviceID)
    }
}
