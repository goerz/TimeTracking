// EntryEditSheet: the iPhone's edit sheet (spec_ios.md §2.7): task, project,
// Start and End pickers, the duration, "Created on", Continue and Delete;
// Done saves, Cancel discards.

import SwiftUI
import TimeTrackingCore

struct EntryEditSheet: View {
    @Bindable var model: PhoneModel
    var entryID: EntryID

    @State private var editor: EntryEditSheetModel?
    @State private var picker: ProjectPickerModel?
    @State private var confirmDelete = false
    @FocusState private var taskFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let editor {
                    form(editor)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.sheet = nil }.accessibilityIdentifier("editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            if await editor?.save() ?? true {
                                model.sheet = nil
                            }
                        }
                    }
                    .accessibilityIdentifier("editor.done")
                }
            }
        }
        .task {
            // The task typed on the card is stored first, so the sheet shows it.
            await model.timer.commitTask()
            let editor = EntryEditSheetModel(store: model.store, clock: model.clock)
            editor.onChange = { await model.localWrite() }
            await editor.load(entryID)
            editor.explanation = model.explanations[entryID]
            self.editor = editor
        }
        .sheet(item: $picker) { picker in
            NavigationStack {
                ProjectPickerView(model: picker) { choice in
                    self.picker = nil
                    if case let .project(id) = choice {
                        Task { await editor?.setProject(id) }
                    }
                } onCancel: {
                    self.picker = nil
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func form(_ editor: EntryEditSheetModel) -> some View {
        Form {
            taskSection(editor)
            timeSection(editor)
            actionSection(editor)
        }
        .alert("Delete this entry?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await editor.delete()
                    model.sheet = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func taskSection(_ editor: EntryEditSheetModel) -> some View {
        Section {
            TextField("Task", text: Bindable(editor).task)
                .focused($taskFocused)
                .accessibilityIdentifier("editor.task")
                .onChange(of: editor.task) { _, text in
                    if taskFocused {
                        Task { await editor.taskEdited(text) }
                    }
                }
                .onChange(of: taskFocused) { _, focused in
                    if !focused {
                        editor.taskField.reset()
                    }
                }
            if taskFocused, !editor.taskField.suggestions.isEmpty {
                TaskSuggestionRows(field: editor.taskField, identifier: "editor.suggestion") { suggestion in
                    taskFocused = false
                    Task { await editor.accept(suggestion) }
                }
            }
            Button {
                picker = ProjectPickerModel(store: model.store, currentProject: editor.projectID, taskMatching: false)
            } label: {
                HStack {
                    AreaDot(color: editor.label.color)
                    Text(editor.label.projectAndClient).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: SymbolName.next).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("editor.project")
        }
    }

    private func timeSection(_ editor: EntryEditSheetModel) -> some View {
        Section {
            DatePicker("Start", selection: Bindable(editor).start)
                .accessibilityIdentifier("editor.start")
            if editor.isRunning {
                LabeledContent("End", value: "Running")
            } else {
                DatePicker("End", selection: Bindable(editor).end)
                    .accessibilityIdentifier("editor.end")
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                LabeledContent("Duration", value: editor.durationText(at: model.clock.now))
                    .accessibilityIdentifier("editor.duration")
            }
            notices(editor)
        }
    }

    private func actionSection(_ editor: EntryEditSheetModel) -> some View {
        Section {
            if !editor.isRunning {
                Button("Continue") {
                    model.sheet = nil
                    Task { await model.timer.continueEntry(entryID) }
                }
                .accessibilityIdentifier("editor.continue")
            }
            Button("Delete", role: .destructive) { confirmDelete = true }
                .accessibilityIdentifier("editor.delete")
        } footer: {
            if let created = editor.createdOn {
                Text(created)
            }
        }
    }

    @ViewBuilder
    private func notices(_ editor: EntryEditSheetModel) -> some View {
        if let explanation = editor.explanation {
            Text(explanation).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("editor.explanation")
        }
        if let message = editor.message {
            Text(message).font(.caption).foregroundStyle(Color.errorText).accessibilityIdentifier("editor.message")
        }
        if let overlap = editor.overlap {
            VStack(alignment: .leading) {
                Text(overlap).font(.caption)
                HStack {
                    Button("Keep") {
                        Task {
                            if await editor.keepOverlap() {
                                model.sheet = nil
                            }
                        }
                    }
                    .accessibilityIdentifier("editor.keepOverlap")
                    Button("Revert") { editor.revertOverlap() }
                        .accessibilityIdentifier("editor.revertOverlap")
                }
                .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("editor.overlap")
        }
    }
}
