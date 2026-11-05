// TimeTrackingFocusFilter: the Focus filter that logs Focus changes as
// presence hints (ios.md §9.3). It forwards to the library's
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
        """
        Records when this Focus turns on and off, for Activity. \
        It can also pause recording Safari sites and automations while the Focus is on.
        """
    )

    @Parameter(title: "Name") var label: String?
    @Parameter(title: "Record Safari Sites and Automations", default: true) var collect: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(label ?? "Focus")",
            subtitle: collect ? "Records the Focus" : "Records the Focus; pauses Safari sites and automations"
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
