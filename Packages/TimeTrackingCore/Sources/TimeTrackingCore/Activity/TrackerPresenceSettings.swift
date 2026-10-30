// TrackerPresenceSettings: the [presence] table of settings.toml
// (spec_activity_tracking.md §7.1). A missing key takes its default.

public import Foundation

/// `[presence]`.
public struct TrackerPresenceSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case idleAfter = "idle_after"
        case passiveApps = "passive_apps"
        case passiveDomains = "passive_domains"
        case passiveLimit = "passive_limit"
    }

    public var idleAfter: TimeInterval = 120
    public var passiveApps = [
        "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.apple.ScreenSharing", "com.apple.QuickTimePlayerX",
    ]
    public var passiveDomains = ["youtube.com", "netflix.com", "meet.google.com"]
    public var passiveLimit: TimeInterval = 3 * 3600

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.idleAfter = try container.duration(.idleAfter, default: fallback.idleAfter)
        self.passiveApps = try container.value(.passiveApps, default: fallback.passiveApps)
        self.passiveDomains = try container.value(.passiveDomains, default: fallback.passiveDomains)
        self.passiveLimit = try container.duration(.passiveLimit, default: fallback.passiveLimit)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(TrackerDuration.format(idleAfter), forKey: .idleAfter)
        try container.encode(passiveApps, forKey: .passiveApps)
        try container.encode(passiveDomains, forKey: .passiveDomains)
        try container.encode(TrackerDuration.format(passiveLimit), forKey: .passiveLimit)
    }
}
