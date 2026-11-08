// ActivityBlock+Devices: whether a block holds time of an iPhone or iPad
// or of synced Safari history, for the Calendar's badges (calendar.md §3.1).

extension ActivityBlock {
    /// The appIDs of the iOS sources' Items (activity_tracking.md §2.3).
    static let iOSAppIDs: Set = [
        ActivityItem.screenTimeAppID, ActivityItem.everythingAppID, "intent", "app", "com.apple.mobilesafari",
    ]

    /// Whether an iPhone or iPad credited foreground time.
    public var hasIOSTime: Bool {
        foreground.contains { Self.iOSAppIDs.contains($0.item.appID) }
    }

    /// Whether synced Safari history of no known device credited foreground time.
    public var hasRemoteTime: Bool {
        foreground.contains { $0.device == ActivityBlockItem.remoteDevice }
    }
}
