// EntryEditorView: the edit popover (spec_timer_window.md §4).

import SwiftUI
import TimeTrackingCore

/// Task, Project, Start and Stop, Duration, Date, the chain lines, Delete.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Task", text: $model.task)
                .focused($focus, equals: .task)
                .onSubmit { Task { await model.commitTask() } }
                .accessibilityIdentifier("editor.task")
            projectChip
            timeFields
            DatePicker("Date", selection: $model.date, displayedComponents: .date)
                .disabled(model.isRunning)
                .onChange(of: model.date) { Task { await model.commitDate() } }
                .accessibilityIdentifier("editor.date")
            notices
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete = true }
                .keyboardShortcut(.delete, modifiers: .command)
                .accessibilityIdentifier("editor.delete")
        }
        .padding(16)
        .frame(width: 320)
        .task {
            model.undoManager = undoManager
            await model.load()
        }
        .onChange(of: focus) { old, _ in
            commitOnFocusLoss(old)
        }
        .onKeyPress(.escape) {
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

    @ViewBuilder private var timeFields: some View {
        HStack {
            timeField("Start", text: $model.startText, field: .start, identifier: "editor.start") {
                await model.commitStart()
            }
            timeField("Stop", text: $model.stopText, field: .stop, identifier: "editor.stop") {
                await model.commitStop()
            }
            .disabled(model.isRunning)
        }
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if model.isRunning {
                LabeledContent("Duration", value: model.durationDisplay(at: context.date))
                    .accessibilityIdentifier("editor.duration")
            } else {
                timeField("Duration", text: $model.durationText, field: .duration, identifier: "editor.duration") {
                    await model.commitDuration()
                }
            }
        }
    }

    @ViewBuilder private var notices: some View {
        ForEach(model.chainLines, id: \.self) { line in
            Text(line).font(.caption).foregroundStyle(.secondary)
        }
        if let message = model.message {
            Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("editor.message")
        }
        if let overlap = model.overlap {
            HStack {
                Text(overlap.text).font(.caption)
                Spacer()
                Button("Keep") { Task { await model.keepOverlap() } }.accessibilityIdentifier("editor.keepOverlap")
                Button("Revert") { model.revertOverlap() }.accessibilityIdentifier("editor.revertOverlap")
            }
            .accessibilityIdentifier("editor.overlap")
        }
    }

    private var projectChip: some View {
        Button {
            picker = makePicker(model.entry.projectID)
        } label: {
            HStack(spacing: 6) {
                AreaDot(color: model.label.color)
                Text(model.label.name)
                if let client = model.label.client {
                    Text("· \(client)").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("p", modifiers: .command)
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
        LabeledContent(title) {
            TextField(title, text: text)
                .labelsHidden()
                .focused($focus, equals: field)
                .onSubmit { Task { await commit() } }
                .accessibilityIdentifier(identifier)
        }
    }

    private func commitOnFocusLoss(_ field: Field?) {
        Task {
            switch field {
            case .task: await model.commitTask()
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
