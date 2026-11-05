// TrackerDeviceSettings: the [devices] table of settings.toml
// (activity_tracking.md §6.1, §7.1). A missing key takes its default.

/// `[devices]`.
public struct TrackerDeviceSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case syncedSafariHistory = "synced_safari_history"
    }

    /// Whether Safari history synced from other devices becomes blocks.
    public var syncedSafariHistory = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.syncedSafariHistory = try container.value(.syncedSafariHistory, default: false)
    }
}
