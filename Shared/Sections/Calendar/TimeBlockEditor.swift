// TimeBlockEditor: the time-block editor, title, project, start, end, and
// notes (spec_calendar.md §4.2).

import SwiftUI
import TimeTrackingCore

/// The time-block editor: title, project, start, end, notes; Delete for existing blocks.
struct TimeBlockEditor: View {
    var model: CalendarModel
    @State private var showsPicker = false

    var body: some View {
        if let draft = model.blockDraft {
            VStack(alignment: .leading, spacing: Design.Spacing.medium) {
                TextField("Title", text: Binding { model.blockDraft?.title ?? "" } set: { model.blockDraft?.title = $0 })
                    .accessibilityIdentifier("calendar.block.title")
                ProjectChipButton(label: model.label(draft.projectID)) { showsPicker = true }
                    .popover(isPresented: $showsPicker) { picker(draft) }
                    .accessibilityIdentifier("calendar.block.project")
                DatePicker("Start", selection: startBinding(draft), displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: endBinding(draft), displayedComponents: [.date, .hourAndMinute])
                TextField("Notes", text: Binding { model.blockDraft?.notes ?? "" } set: { model.blockDraft?.notes = $0 }, axis: .vertical)
                    .lineLimit(3 ... 6)
                HStack {
                    if let id = draft.eventID {
                        Button("Delete", role: .destructive) { Task { await model.deleteTimeBlocks([id]) } }
                    }
                    Spacer()
                    Button("Cancel") { model.blockDraft = nil }.keyboardShortcut(.cancelAction)
                    Button("Save") { Task { await model.saveTimeBlock() } }
                        .keyboardShortcut(.defaultAction)
                    #if os(macOS)
                        .buttonStyle(.borderedProminent)
                    #endif
                }
            }
            .padding()
            .frame(width: 320)
        }
    }

    private func picker(_ draft: TimeBlockDraft) -> some View {
        ProjectPickerView(model: ProjectPickerModel(store: model.store, currentProject: draft.projectID, taskMatching: false)) { choice in
            if case let .project(id) = choice {
                model.blockDraft?.projectID = id
            }
            showsPicker = false
        }
    }

    private func startBinding(_ draft: TimeBlockDraft) -> Binding<Date> {
        Binding { draft.interval.start } set: { start in
            model.blockDraft?.interval = DateInterval(start: start, end: max(start + 60, draft.interval.end))
        }
    }

    private func endBinding(_ draft: TimeBlockDraft) -> Binding<Date> {
        Binding { draft.interval.end } set: { end in
            model.blockDraft?.interval = DateInterval(start: draft.interval.start, end: max(draft.interval.start + 60, end))
        }
    }
}
