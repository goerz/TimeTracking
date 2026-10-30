// TrackerSettingsModel: the Tracker pane's settings file and activity logs,
// and the exclusion draft from the Activity section (spec_activity_tracking.md
// §7, §7.4; spec_planner_activity.md §4).

import Foundation
import Observation
import os
import TimeTrackingCore

/// The exclusion lists of §7.2, by their key in `[privacy]`.
enum ExclusionList: String, CaseIterable, Identifiable {
    case excludePaths = "exclude_paths"
    case excludeKeywords = "exclude_keywords"
    case excludeTmuxSessions = "exclude_tmux_sessions"
    case privateAgentPaths = "private_agent_paths"
    case nameOnlyApps = "name_only_apps"
    case excludeApps = "exclude_apps"
    case privateDomains = "private_domains"
    case excludeDomains = "exclude_domains"
    case excludeTitleKeywords = "exclude_title_keywords"

    var id: String {
        rawValue
    }

    /// The key in `settings.toml`.
    var key: String {
        rawValue
    }

    /// What an entry is, for the draft's field.
    var entryName: String {
        switch self {
        case .excludeApps, .nameOnlyApps: "App (bundle identifier)"
        case .excludeTmuxSessions: "tmux session"
        case .excludeDomains, .privateDomains: "Site (domain)"
        case .excludePaths, .privateAgentPaths: "Folder"
        case .excludeKeywords, .excludeTitleKeywords: "Keyword"
        }
    }

    /// The list as the pane names it, "excluded apps".
    var displayName: String {
        switch self {
        case .excludeApps: "excluded apps"
        case .nameOnlyApps: "apps recorded by name only"
        case .excludeDomains: "excluded sites"
        case .privateDomains: "private sites"
        case .excludePaths: "excluded folders"
        case .privateAgentPaths: "private coding agent folders"
        case .excludeTmuxSessions: "excluded tmux sessions"
        case .excludeKeywords: "excluded keywords"
        case .excludeTitleKeywords: "excluded title keywords"
        }
    }

    /// "excluded apps (exclude_apps)": the name, and the key to find it in the file.
    var displayNameWithKey: String {
        "\(displayName) (\(key))"
    }
}

/// `settings.toml` and the block log folder. The file is the user's: the
/// app writes it only to create the commented default file and to add an
/// exclusion drafted in the Activity section, keeping every other byte.
@Observable
final class TrackerSettingsModel {
    @ObservationIgnored let settingsURL: URL?
    /// An unsaved, focused exclusion from the Activity section.
    var pendingExclusion: PendingExclusion?
    /// The last exclusion added, confirmed under the settings file.
    var lastAdded: PendingExclusion?
    /// What went wrong with the file, shown under it.
    private(set) var message: String?

    init(settingsURL: URL?) {
        self.settingsURL = settingsURL
    }

    /// `blocks/` next to the settings file: the activity logs.
    var logsURL: URL? {
        settingsURL?.deletingLastPathComponent().appending(path: "blocks", directoryHint: .isDirectory)
    }

    /// A path as shown in the pane, with `~` for the home folder.
    static func displayPath(_ url: URL?) -> String {
        guard let path = url?.path else {
            return "Not available"
        }
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Writes the default file when there is none, so it can be opened. An
    /// iCloud Drive placeholder (another Mac wrote the file and this one has
    /// not downloaded it) starts the download instead and returns `false`.
    @discardableResult
    func ensureFile() -> Bool {
        guard let settingsURL else {
            return false
        }
        let manager = FileManager.default
        if manager.fileExists(atPath: settingsURL.path) {
            message = nil
            return true
        }
        let placeholder = settingsURL.deletingLastPathComponent().appending(path: ".\(settingsURL.lastPathComponent).icloud")
        if manager.fileExists(atPath: placeholder.path) {
            try? manager.startDownloadingUbiquitousItem(at: settingsURL)
            message = "The settings file is still downloading from iCloud Drive. Try again in a moment."
            return false
        }
        do {
            try manager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(TrackerSettings.defaultFileContents.utf8).write(to: settingsURL, options: .withoutOverwriting)
            message = nil
            return true
        } catch {
            message = Self.message(for: error)
            return false
        }
    }

    /// The draft's Add button: appends the value to its list in the file,
    /// leaving the rest of the file as it was.
    func addPendingExclusion() {
        guard let pending = pendingExclusion, !pending.value.trimmed.isEmpty, let settingsURL, ensureFile() else {
            return
        }
        do {
            let text = try String(contentsOf: settingsURL, encoding: .utf8)
            let edited = try TrackerSettingsText.appending(pending.value.trimmed, to: pending.list.key, in: "privacy", of: text)
            if edited != text {
                try Data(edited.utf8).write(to: settingsURL, options: .atomic)
            }
            lastAdded = PendingExclusion(list: pending.list, value: pending.value.trimmed)
            pendingExclusion = nil
            message = nil
        } catch {
            message = Self.message(for: error)
        }
    }

    /// The line under the settings file for a failed edit: the settings
    /// error's own sentence, else "Couldn't write the settings file: …".
    static func message(for error: any Error) -> String {
        if case let .invalidSettings(message) = error as? ActivityError {
            return message
        }
        Logging.logger(category: "Tracker").error("settings.toml: \(String(describing: error), privacy: .public)")
        return "Couldn't write the settings file: \(error.localizedDescription)"
    }

    /// Entries of `list` in the file as it is now.
    func entries(_ list: ExclusionList) -> [String] {
        guard let settingsURL, let settings = try? TrackerSettings(contentsOf: settingsURL) else {
            return []
        }
        return settings.privacy.list(list)
    }
}
