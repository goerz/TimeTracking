// TrackerSettings: the model of settings.toml (spec_activity_tracking.md §7.1).

public import Foundation
import TOMLKit

/// The tracker settings in `settings.toml` of the shared folder.
///
/// Every key is optional in the file; a missing key or table takes its
/// default, so `TrackerSettings.defaults` decodes from an empty file.
/// Durations are written `"30s"`, `"5m"`, `"3h"` and held in seconds.
public struct TrackerSettings: Sendable, Hashable, Codable {
    enum CodingKeys: String, CodingKey {
        case presence, blocks, files, terminal, devices, privacy, browser
    }

    public var presence = TrackerPresenceSettings()
    public var blocks = TrackerBlockSettings()
    public var files = TrackerFileSettings()
    public var terminal = TrackerTerminalSettings()
    public var devices = TrackerDeviceSettings()
    public var privacy = TrackerPrivacySettings()
    public var browser = TrackerBrowserSettings()

    public init() {}

    /// The defaults of §7.1, equal to `TrackerSettings.defaultFileContents` decoded.
    public static let defaults = Self()

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.presence = try container.value(.presence, default: TrackerPresenceSettings())
        self.blocks = try container.value(.blocks, default: TrackerBlockSettings())
        self.files = try container.value(.files, default: TrackerFileSettings())
        self.terminal = try container.value(.terminal, default: TrackerTerminalSettings())
        self.devices = try container.value(.devices, default: TrackerDeviceSettings())
        self.privacy = try container.value(.privacy, default: TrackerPrivacySettings())
        self.browser = try container.value(.browser, default: TrackerBrowserSettings())
    }

    /// Parses the text of `settings.toml`.
    public init(tomlText: String) throws(ActivityError) {
        do {
            self = try TOMLDecoder().decode(Self.self, from: tomlText)
        } catch {
            throw .invalidSettings(String(describing: error))
        }
    }

    /// Reads `url`; a missing file gives the defaults.
    public init(contentsOf url: URL) throws(ActivityError) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.init()
            return
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw .fileSystem("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        try self.init(tomlText: text)
    }

    /// The TOML text the Tracker pane writes. It holds every key; the
    /// comments of the default file are not kept.
    public func tomlText() throws(ActivityError) -> String {
        do {
            return try TOMLEncoder().encode(self)
        } catch {
            throw .invalidSettings(String(describing: error))
        }
    }

    /// The exclusions of `[privacy]`, with `~` standing for `homeDirectory`.
    public func exclusions(homeDirectory: String = NSHomeDirectory()) -> ExclusionRules {
        ExclusionRules(privacy: privacy, homeDirectory: homeDirectory)
    }
}
