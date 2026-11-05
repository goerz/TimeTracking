// TrackerSettings: the model of settings.toml (activity_tracking.md §7.1).

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
            throw .invalidSettings(Self.message(for: error))
        }
    }

    /// What the Tracker pane shows for a file that does not decode: "The
    /// settings file has an error on line 12: expected '='. Fix it in the editor."
    static func message(for error: any Error) -> String {
        if let error = error as? TOMLParseError {
            let description = error.description.trimmingCharacters(in: CharacterSet(charactersIn: ". \n"))
            return "The settings file has an error on line \(error.source.begin.line): \(description). Fix it in the editor."
        }
        if case let .typeMismatch(type, context) = error as? DecodingError, type == TOMLArray.self || "\(type)".hasPrefix("Array"),
           let key = context.codingPath.last?.stringValue
        {
            let table = context.codingPath.dropLast().map(\.stringValue).joined(separator: ".")
            return TrackerSettingsText.notAList(key, in: table)
        }
        if let error = error as? DecodingError {
            let (path, problem): ([any CodingKey], String) = switch error {
            case let .typeMismatch(_, context), let .valueNotFound(_, context):
                (context.codingPath, "has a value of the wrong kind")
            case let .dataCorrupted(context):
                (context.codingPath, "can't be used: \(context.debugDescription)")
            case let .keyNotFound(key, context):
                (context.codingPath + [key], "is missing")
            @unknown default:
                ([], "has a value that can't be used")
            }
            let setting = path.map(\.stringValue).filter { Int($0) == nil }.joined(separator: ".")
            let name = setting.isEmpty ? "A setting" : setting
            return "In the settings file, \(name) \(problem). Fix it in the editor."
        }
        return "The settings file can't be read. Fix it in the editor."
    }

    /// Reads `url`; a missing file gives the defaults.
    /// The settings of the file at `url`, the defaults when there is none.
    /// A file iCloud Drive holds only as a placeholder (`.<name>.icloud`)
    /// throws, after asking for its download: its exclusions are unknown,
    /// so callers keep the settings they have.
    public init(contentsOf url: URL) throws(ActivityError) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let placeholder = url.deletingLastPathComponent()
                .appending(path: ".\(url.lastPathComponent).icloud", directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: placeholder.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                throw .fileSystem("\(url.lastPathComponent) is not downloaded from iCloud Drive yet")
            }
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
            throw .invalidSettings("Couldn't write the settings file: \(error.localizedDescription)")
        }
    }

    /// The exclusions of `[privacy]`, with `~` standing for `homeDirectory`.
    public func exclusions(homeDirectory: String = NSHomeDirectory()) -> ExclusionRules {
        ExclusionRules(privacy: privacy, homeDirectory: homeDirectory)
    }
}
