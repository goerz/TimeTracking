// EntryEditorView: the edit popover (timer.md §4).

import SwiftUI
import TimeTrackingCore

/// Task, Project, Start and Stop, Duration, Date as labeled rows; the
/// notices; Delete.
struct EntryEditorView: View {
    @Bindable var model: EntryEditorModel
    var makePicker: (ProjectID?) -> ProjectPickerModel
    var onClose: () -> Void

    @Environment(\.undoManager) private var undoManager
    @FocusState private var focus: Field?
    @State private var picker: ProjectPickerModel?
    @State private var confirmDelete = false

    private enum Field: Hashable {
        case task
        case start
        case stop
        case duration
    }

    /// The width of the time and duration fields.
    private static let timeFieldWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Design.Spacing.small, verticalSpacing: Design.Spacing.small) {
                subjectRows
                timeRows
            }
            notices
            Divider()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Entry…", systemImage: SymbolName.delete)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .keyboardShortcut(.delete, modifiers: .command)
            .accessibilityIdentifier("editor.delete")
        }
        .padding(Design.Spacing.large)
        .frame(width: 340)
        .task {
            model.undoManager = undoManager
            await model.load()
        }
        .onChange(of: focus) { old, _ in
            commitOnFocusLoss(old)
        }
        .onKeyPress(.escape) {
            // The picker's key presses arrive here: Escape closes it alone.
            if picker != nil {
                picker = nil
                return .handled
            }
            if model.taskField.escape(text: model.task) {
                return .handled
            }
            if !model.revertFields() {
                onClose()
            }
            return .handled
        }
        .alert("Delete this entry?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await model.delete() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Task and Project.
    @ViewBuilder private var subjectRows: some View {
        GridRow {
            rowLabel("Task")
            TextField("Task", text: taskText, prompt: Text("No task"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .task)
                .onSubmit { Task { await model.submitTask() } }
                .onKeyPress(.upArrow) { moveSuggestion(-1) }
                .onKeyPress(.downArrow) { moveSuggestion(1) }
                .onKeyPress(.tab) {
                    guard let suggestion = model.taskField.acceptSuggestion() else {
                        return .ignored
                    }
                    Task { await model.accept(suggestion) }
                    return .handled
                }
                .accessibilityIdentifier("editor.task")
        }
        if focus == .task, model.taskField.isShowingSuggestions {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.taskField.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        SuggestionRow(field: model.taskField, index: index, suggestion: suggestion) {
                            Task { await model.accept(suggestion) }
                        }
                        .accessibilityIdentifier("editor.suggestion.\(index)")
                    }
                }
            }
        }
        GridRow(alignment: .center) {
            rowLabel("Project")
            projectChip
        }
    }

    /// User edits go through this binding; programmatic changes do not.
    private var taskText: Binding<String> {
        Binding {
            model.task
        } set: { text in
            // AppKit writes the value back on focus; only real edits count.
            guard text != model.task else {
                return
            }
            model.task = text
            model.taskField.textChanged(text)
            Task { await model.taskEdited(text) }
        }
    }

    private func moveSuggestion(_ offset: Int) -> KeyPress.Result {
        guard model.taskField.isShowingSuggestions else {
            return .ignored
        }
        model.taskField.move(by: offset)
        return .handled
    }

    /// Start, Stop, Duration, and Date.
    @ViewBuilder private var timeRows: some View {
        GridRow {
            rowLabel("Start")
            timeField("Start", text: $model.startText, field: .start, identifier: "editor.start") {
                await model.commitStart()
            }
        }
        GridRow {
            rowLabel("Stop")
            if model.isRunning {
                Text("running").foregroundStyle(.secondary).accessibilityIdentifier("editor.stop")
            } else {
                timeField("Stop", text: $model.stopText, field: .stop, identifier: "editor.stop") {
                    await model.commitStop()
                }
            }
        }
        GridRow {
            rowLabel("Duration")
            duration
        }
        GridRow(alignment: .center) {
            rowLabel("Date")
            DatePicker("Date", selection: $model.date, displayedComponents: .date)
                .labelsHidden()
                .fixedSize()
                .disabled(model.isRunning)
                .onChange(of: model.date) { Task { await model.commitDate() } }
                .accessibilityIdentifier("editor.date")
        }
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// The live elapsed time while running, else the editable duration.
    /// Only the running text ticks; the field is never redrawn while edited.
    @ViewBuilder private var duration: some View {
        if model.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(model.durationDisplay(at: model.clock.now))
                    .monospacedDigit()
                    .accessibilityIdentifier("editor.duration")
            }
        } else {
            timeField("Duration", text: $model.durationText, field: .duration, identifier: "editor.duration") {
                await model.commitDuration()
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if model.message != nil || model.overlap != nil {
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                if let message = model.message {
                    ErrorLine(text: message)
                        .accessibilityIdentifier("editor.message")
                }
                if let overlap = model.overlap {
                    VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                        Label(overlap.text, systemImage: SymbolName.warning).font(.caption)
                        HStack {
                            Button("Keep") { Task { await model.keepOverlap() } }
                                .accessibilityIdentifier("editor.keepOverlap")
                            Button("Revert") { model.revertOverlap() }
                                .accessibilityIdentifier("editor.revertOverlap")
                        }
                        .controlSize(.small)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("editor.overlap")
                }
            }
        }
    }

    private var projectChip: some View {
        ProjectChipButton(label: model.label) {
            picker = makePicker(model.entry.projectID)
        }
        .keyboardShortcut("j", modifiers: .command)
        .accessibilityIdentifier("editor.project")
        .popover(item: $picker) { picker in
            ProjectPickerView(model: picker) { choice in
                self.picker = nil
                if case let .project(id) = choice {
                    Task { await model.setProject(id) }
                }
            } onCancel: {
                self.picker = nil
            }
        }
    }

    private func timeField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        identifier: String,
        commit: @escaping () async -> Void
    ) -> some View {
        TextField(title, text: text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: Self.timeFieldWidth)
            .focused($focus, equals: field)
            .onSubmit { Task { await commit() } }
            .accessibilityIdentifier(identifier)
    }

    private func commitOnFocusLoss(_ field: Field?) {
        Task {
            switch field {
            case .task:
                model.taskField.reset()
                await model.commitTask()
            case .start: await model.commitStart()
            case .stop: await model.commitStop()
            case .duration: await model.commitDuration()
            case nil: break
            }
        }
    }
}

extension ProjectPickerModel: Identifiable {
    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
