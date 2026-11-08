// ActivityDeviceName: a device's name in the Activity section and the
// Calendar (activity.md §1.3).

/// A device as the Activity section and the Calendar name it.
public enum ActivityDeviceName {
    /// `remote` (synced Safari history of no known device) reads "Other devices (Safari)".
    public static func display(_ device: String) -> String {
        device == ActivityBlockItem.remoteDevice ? "Other devices (Safari)" : device
    }
}
