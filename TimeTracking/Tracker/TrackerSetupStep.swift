// TrackerSetupStep: one row of the Tracker pane's setup checklist and its
// info popover (spec_activity_tracking.md §7.4).

import Foundation

/// One setup step of the Tracker pane.
struct TrackerSetupStep: Identifiable, Equatable {
    /// The mark: ✓ active, ! fallback or off, – no health record yet.
    enum Mark: String {
        case done = "✓"
        case attention = "!"
        case unknown = "–"

        /// What VoiceOver reads for the mark.
        var accessibilityLabel: String {
            switch self {
            case .done: "Done"
            case .attention: "Needs attention"
            case .unknown: "Not checked yet"
            }
        }
    }

    enum Action: Equatable {
        case enableTracker
        case openLoginItems
        case openSettings(anchor: String)
        /// "Show <name> in Finder": reveals that bundle.
        case showInFinder(name: String, url: URL)
        case restartTracker
        case openAtLogin
        case copySnippet(String)
        case noAction

        /// The button title.
        var title: String {
            switch self {
            case .enableTracker: "Enable Tracker"
            case .openLoginItems: "Open Login Items"
            case .openSettings: "Open System Settings"
            case let .showInFinder(name, _): "Show \(name) in Finder"
            case .restartTracker: "Restart Tracker"
            case .openAtLogin: "Open at Login"
            case .copySnippet: "Copy Snippet"
            case .noAction: ""
            }
        }

        /// The last part of the button's accessibility identifier,
        /// `tracker.action.<step>.<suffix>`.
        var identifierSuffix: String {
            switch self {
            case .enableTracker: "enable"
            case .openLoginItems: "loginItems"
            case .openSettings: "settings"
            case .showInFinder: "finder"
            case .restartTracker: "restart"
            case .openAtLogin: "openAtLogin"
            case .copySnippet: "copy"
            case .noAction: "none"
            }
        }
    }

    var id: String
    var title: String
    /// One line under the title: what the step gives while on ("On: …"),
    /// what applies while off ("Off: …"), or what it does before the
    /// tracker has reported; `nil` for steps that need no explanation.
    var detail: String?
    var mark: Mark
    var actions: [Action]
    /// Numbered steps, shown while the step is not done.
    var guidance: [String] = []
    /// Why the grant goes to this bundle.
    var note = ""
    /// The row's info button: what the step does and what to do.
    var info: TrackerSetupInfo?
}

/// The popover of a setup row's info button.
struct TrackerSetupInfo: Equatable {
    var title: String
    var paragraphs: [String]
    /// The text to copy, shown in a monospaced box with a Copy button.
    var snippet: String?
}
