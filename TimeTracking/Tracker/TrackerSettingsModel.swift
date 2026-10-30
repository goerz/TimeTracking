// TrackerSettingsModel: the Tracker pane's exclusions, options, and
// maintenance (spec_activity_tracking.md §7.2 to §7.4).

import Foundation
import Observation
import TimeTrackingCore

/// The nine exclusion lists of §7.2.
enum ExclusionList: String, CaseIterable, Identifiable {
    case excludePaths
    case excludeKeywords
    case excludeTmuxSessions
    case privateAgentPaths
    case nameOnlyApps
    case excludeApps
    case privateDomains
    case excludeDomains
    case excludeTitleKeywords

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .excludePaths: "Excluded folders"
        case .excludeKeywords: "Excluded path keywords"
        case .excludeTmuxSessions: "Excluded tmux sessions"
        case .privateAgentPaths: "Private agent folders"
        case .nameOnlyApps: "Apps recorded by name only"
        case .excludeApps: "Excluded apps"
        case .privateDomains: "Private domains"
        case .excludeDomains: "Excluded domains"
        case .excludeTitleKeywords: "Excluded title keywords"
        }
    }

    /// How entries are picked: installed apps, an open panel, or text.
    var input: Input {
        switch self {
        case .nameOnlyApps, .excludeApps: .app
        case .excludePaths, .privateAgentPaths: .folder
        default: .text
        }
    }

    enum Input {
        case app
        case folder
        case text
    }

    var keyPath: WritableKeyPath<TrackerPrivacySettings, [String]> {
        switch self {
        case .excludePaths: \.excludePaths
        case .excludeKeywords: \.excludeKeywords
        case .excludeTmuxSessions: \.excludeTmuxSessions
        case .privateAgentPaths: \.privateAgentPaths
        case .nameOnlyApps: \.nameOnlyApps
        case .excludeApps: \.excludeApps
        case .privateDomains: \.privateDomains
        case .excludeDomains: \.excludeDomains
        case .excludeTitleKeywords: \.excludeTitleKeywords
        }
    }
}

/// Reads and writes `settings.toml` (the pane writes nothing else) and sends
/// the rewrite commands.
@Observable
final class TrackerSettingsModel {
    @ObservationIgnored let settingsURL: URL?
    @ObservationIgnored let commands: TrackerCommandSending
    @ObservationIgnored let clock: any Clock

    private(set) var settings = TrackerSettings.defaults
    /// The exclusion just saved, offering "Also remove it from past logs…".
    var offerReapply: ExclusionList?
    /// The reapply range, default the block log's first month to today.
    var reapplyFrom: Date
    var reapplyTo: Date
    var forgetDay: Date
    private(set) var message: String?
    /// An unsaved, focused exclusion from the Activity section (spec_planner_activity.md §4).
    var pendingExclusion: PendingExclusion?

    init(settingsURL: URL?, commands: TrackerCommandSending, clock: any Clock, firstLogDay: Date? = nil) {
        self.settingsURL = settingsURL
        self.commands = commands
        self.clock = clock
        self.reapplyFrom = firstLogDay ?? clock.now
        self.reapplyTo = clock.now
        self.forgetDay = clock.now
    }

    func load() {
        guard let settingsURL, let loaded = try? TrackerSettings(contentsOf: settingsURL) else {
            return
        }
        settings = loaded
    }

    func entries(_ list: ExclusionList) -> [String] {
        settings.privacy[keyPath: list.keyPath]
    }

    /// Adds an entry and saves; then offers to apply it to past logs.
    func add(_ value: String, to list: ExclusionList) {
        let value = value.trimmed
        guard !value.isEmpty, !entries(list).contains(value) else {
            return
        }
        settings.privacy[keyPath: list.keyPath].append(value)
        if save() {
            offerReapply = list
        }
    }

    func remove(_ value: String, from list: ExclusionList) {
        settings.privacy[keyPath: list.keyPath].removeAll { $0 == value }
        save()
    }

    /// "Idle after" in seconds.
    var idleAfterSeconds: Int {
        get { Int(settings.presence.idleAfter) }
        set {
            settings.presence.idleAfter = TimeInterval(newValue)
            save()
        }
    }

    /// Watched folders (`roots`), one per line.
    var roots: [String] {
        get { settings.files.roots }
        set {
            settings.files.roots = newValue
            save()
        }
    }

    var useSyncedSafariHistory: Bool {
        get { settings.devices.syncedSafariHistory }
        set {
            settings.devices.syncedSafariHistory = newValue
            save()
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let settingsURL else {
            return true
        }
        do {
            let text = try settings.tomlText()
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: settingsURL, options: .atomic)
            message = nil
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// Confirming "Also remove it from past logs…" or "Reapply Exclusions…":
    /// exactly one `reapply-exclusions <from> <to>`.
    func reapplyExclusions() async {
        offerReapply = nil
        let command = "reapply-exclusions \(Self.day(reapplyFrom)) \(Self.day(reapplyTo))"
        await report(commands.send(command))
    }

    /// "Forget a Day…" after confirmation.
    func forget() async {
        await report(commands.send("forget-day \(Self.day(forgetDay))"))
    }

    private func report(_ result: TrackerCommandResult) {
        switch result {
        case .accepted: message = nil
        case let .rejected(reason): message = reason
        }
    }

    static func day(_ date: Date) -> String {
        TrackingCalendar(timeZone: .current).day(containing: date).description
    }
}
