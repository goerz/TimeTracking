// TimeTrackingFocusFilter: the Focus filter that logs Focus changes as
// presence hints (spec_ios.md §9.3). It forwards to the library's
// CollectionLog, which decides between `on` and `off`.

import AppIntents
import Foundation
import TimeTrackingCore

/// Performed with its parameters when the Focus turns on, and with the
/// default parameters (no label) when it ends.
struct TimeTrackingFocusFilter: SetFocusFilterIntent {
    /// The suggestions, one per common Focus (the system does not tell the
    /// app which Focuses exist).
    static let suggestedLabels = ["Work", "Personal", "Sleep", "Fitness", "Reading", "Driving"]

    static let title: LocalizedStringResource = "Log Activity"
    static let description: IntentDescription? = IntentDescription(
        "Logs when this Focus turns on and off in this device's activity log, and can pause the Safari and automation collectors."
    )

    @Parameter(title: "Label") var label: String?
    @Parameter(title: "Collect Safari and Automations", default: true) var collect: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(label ?? "Focus")",
            subtitle: collect ? "Logs the Focus" : "Logs the Focus; pauses Safari and automations"
        )
    }

    static func suggestedFocusFilters(for _: FocusFilterSuggestionContext) -> [Self] {
        suggestedLabels.map { name in
            let filter = Self()
            filter.label = name
            return filter
        }
    }

    func perform() throws -> some IntentResult {
        try CollectionLog.extensionLog(identity: AppIdentity.main)?.focusFilterPerformed(label: label, collect: collect)
        return .result()
    }
}
