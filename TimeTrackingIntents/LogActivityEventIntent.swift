// LogActivityEventIntent: the "Log Activity Event" action for Shortcuts
// personal automations (spec_ios.md §6.1, §9.4). It forwards to the
// library's CollectionLog; the collection file is the only thing it writes.

import AppIntents
import Foundation
import TimeTrackingCore

/// The kinds of `ActivityEventKind` as Shortcuts shows them.
enum ActivityEventKindValue: String, AppEnum {
    case appOpened
    case appClosed
    case arrived
    case left
    case chargerConnected
    case chargerDisconnected
    case custom

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Activity Event"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .appOpened: "App Opened",
        .appClosed: "App Closed",
        .arrived: "Arrived",
        .left: "Left",
        .chargerConnected: "Charger Connected",
        .chargerDisconnected: "Charger Disconnected",
        .custom: "Custom",
    ]

    var kind: ActivityEventKind {
        ActivityEventKind(rawValue: rawValue) ?? .custom
    }
}

/// Appends an `intent` line with the automation's label and kind.
struct LogActivityEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Activity Event"
    static let description = IntentDescription(
        "Records a named moment for Activity, for example when an app opens or closes, or when you arrive or leave."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Name", requestValueDialog: "What should it be called?") var label: String
    @Parameter(title: "Type", default: .custom) var kind: ActivityEventKindValue

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$kind) for \(\.$label)")
    }

    func perform() throws -> some IntentResult {
        try CollectionLog.extensionLog(identity: AppIdentity.main)?.logIntent(label: label, kind: kind.kind)
        return .result()
    }
}
