// CandidateText: a suggestion candidate's "Project · Task"
// (spec_calendar.md §2.3, §3.2).

import TimeTrackingCore

/// "Project · Task" of a candidate.
enum CandidateText {
    @MainActor
    static func title(_ candidate: SuggestionCandidate, model: CalendarModel) -> String {
        [model.project(candidate.projectID)?.name ?? "No project", candidate.task].compactMap(\.self).joined(separator: " · ")
    }
}
