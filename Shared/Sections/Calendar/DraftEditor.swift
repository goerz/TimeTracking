// DraftEditor: the edit popover on a provisional entry
// (calendar.md §2.3).

import SwiftUI
import TimeTrackingCore

/// The edit popover on a provisional entry: times, project, and task, the
/// task field suggesting earlier tasks as in the Timer.
struct DraftEditor: View {
    var model: CalendarModel
    @State private var showsPicker = false
    @FocusState private var taskFocused: Bool

    var body: some View {
        if let draft = model.draft {
            VStack(alignment: .leading, spacing: Design.Spacing.medium) {
                Text(CalendarText.range(draft.interval.start, draft.interval.end, zone: model.calendar.timeZone))
                    .font(.headline)
                projectButton(draft)
                taskField
                if taskFocused, field.isShowingSuggestions {
                    suggestions
                }
                HStack {
                    // While suggestions show, Escape and Return belong to the task field.
                    Button("Cancel", role: .cancel) { model.draft = nil }
                        .keyboardShortcut(field.isShowingSuggestions ? nil : .cancelAction)
                    Spacer()
                    Button("Save") { Task { await model.commitDraft() } }
                    #if os(macOS)
                        .buttonStyle(.borderedProminent)
                    #endif
                        .keyboardShortcut(field.isShowingSuggestions ? nil : .defaultAction)
                        .accessibilityIdentifier("calendar.draft.save")
                }
            }
            .padding()
            .frame(width: 300)
            .onAppear {
                field.reset()
                taskFocused = true
            }
            .onDisappear { field.reset() }
        }
    }

    private var field: TaskFieldModel {
        model.draftTaskField
    }

    private var taskField: some View {
        TextField("Task", text: taskText)
            .focused($taskFocused)
            .onSubmit { Task { await model.submitDraft() } }
            .onKeyPress(.upArrow) { moveSuggestion(-1) }
            .onKeyPress(.downArrow) { moveSuggestion(1) }
            .onKeyPress(.tab) {
                guard let suggestion = field.acceptSuggestion() else {
                    return .ignored
                }
                model.acceptDraftSuggestion(suggestion)
                return .handled
            }
            .onKeyPress(.escape) {
                field.escape(text: model.draft?.task ?? "") ? .handled : .ignored
            }
            .accessibilityIdentifier("calendar.draft.task")
    }

    /// User edits go through this binding; programmatic changes do not.
    private var taskText: Binding<String> {
        Binding {
            model.draft?.task ?? ""
        } set: { text in
            // AppKit writes the value back on focus; only real edits count.
            guard text != model.draft?.task else {
                return
            }
            model.draft?.task = text
            field.textChanged(text)
            Task { await model.draftTaskEdited(text) }
        }
    }

    private var suggestions: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(field.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    SuggestionRow(field: field, index: index, suggestion: suggestion) {
                        model.acceptDraftSuggestion(suggestion)
                    }
                    .accessibilityIdentifier("calendar.draft.suggestion.\(index)")
                }
            }
        #else
            TaskSuggestionRows(field: field, identifier: "calendar.draft.suggestion") { suggestion in
                model.acceptDraftSuggestion(suggestion)
            }
        #endif
    }

    private func moveSuggestion(_ offset: Int) -> KeyPress.Result {
        guard field.isShowingSuggestions else {
            return .ignored
        }
        field.move(by: offset)
        return .handled
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
}
