// DraftEditor: the edit popover on a provisional entry
// (spec_planner_calendar.md §2.3).

import SwiftUI
import TimeTrackingCore

/// The edit popover on a provisional entry: times, project, task, and the
/// other candidates under the task field.
struct DraftEditor: View {
    var model: CalendarModel
    @State private var showsPicker = false
    @FocusState private var taskFocused: Bool

    var body: some View {
        if let draft = model.draft {
            VStack(alignment: .leading, spacing: 10) {
                Text(CalendarText.range(draft.interval.start, draft.interval.end, zone: model.calendar.timeZone))
                    .font(.headline)
                projectButton(draft)
                TextField("Task", text: Binding { model.draft?.task ?? "" } set: { model.draft?.task = $0 })
                    .focused($taskFocused)
                    .onSubmit { Task { await model.commitDraft() } }
                    .accessibilityIdentifier("calendar.draft.task")
                candidates(draft)
                HStack {
                    Button("Cancel", role: .cancel) { model.draft = nil }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") { Task { await model.commitDraft() } }
                    #if os(macOS)
                        .buttonStyle(.borderedProminent)
                    #endif
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("calendar.draft.save")
                }
            }
            .padding()
            .frame(width: 300)
            .onAppear { taskFocused = true }
        }
    }

    private func projectButton(_ draft: CalendarDraft) -> some View {
        ProjectChipButton(label: model.label(draft.projectID)) { showsPicker = true }
            .popover(isPresented: $showsPicker) {
                ProjectPickerView(model: ProjectPickerModel(
                    store: model.store,
                    currentProject: draft.projectID,
                    taskMatching: false
                )) { choice in
                    if case let .project(id) = choice {
                        model.draft?.projectID = id
                    }
                    showsPicker = false
                }
            }
            .accessibilityIdentifier("calendar.draft.project")
    }

    @ViewBuilder
    private func candidates(_ draft: CalendarDraft) -> some View {
        let others = draft.candidates.filter { $0.projectID != draft.projectID || ($0.task ?? "") != draft.task }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(others.prefix(4).enumerated()), id: \.offset) { _, candidate in
                    Button {
                        model.draft?.projectID = candidate.projectID
                        model.draft?.task = candidate.task ?? model.draft?.task ?? ""
                    } label: {
                        HStack {
                            Text(CandidateText.title(candidate, model: model))
                            Spacer()
                            ConfidenceMeter(candidate: candidate)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption)
        }
    }
}
