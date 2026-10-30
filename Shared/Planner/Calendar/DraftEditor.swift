// CalendarPopovers: the draft's edit popover, the overlap question, the
// block popover, and the time-block editor (spec_planner_calendar.md §2.3,
// §2.6, §3.2, §4.2).

import SwiftUI
import TimeTrackingCore

/// The edit popover on a provisional entry: times, project, task, and the
/// other candidates under the task field.
struct DraftEditor: View {
    @Bindable var model: CalendarModel
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
        Button {
            showsPicker = true
        } label: {
            HStack {
                AreaDot(color: model.entries.first { $0.project?.id == draft.projectID }?.area?.color)
                Text(model.project(draft.projectID)?.name ?? "No project")
            }
        }
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

/// "Project · Task" of a candidate.
enum CandidateText {
    @MainActor
    static func title(_ candidate: SuggestionCandidate, model: CalendarModel) -> String {
        [model.project(candidate.projectID)?.name ?? "No project", candidate.task].compactMap(\.self).joined(separator: " · ")
    }
}

/// The four-segment confidence meter.
struct ConfidenceMeter: View {
    var candidate: SuggestionCandidate?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < (candidate?.meterSegments ?? 0) ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 8)
            }
        }
        .help(candidate.map { "Confidence \(Int(($0.confidence * 100).rounded()))%" } ?? "No confident suggestion")
    }
}

/// Overlaps "Standup" (11:00 to 11:30) by 12 min. [Trim] [Overlap] [Cancel]
struct OverlapPopover: View {
    var model: CalendarModel

    var body: some View {
        if let pending = model.pendingOverlap {
            VStack(alignment: .leading, spacing: 10) {
                Label(pending.prompt.text(in: model.calendar.timeZone), systemImage: "exclamationmark.triangle")
                HStack {
                    Button("Trim") { Task { await model.resolveOverlap(.trim) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(pending.prompt.trimmed == nil)
                        .accessibilityIdentifier("calendar.overlap.trim")
                    Button("Overlap") { Task { await model.resolveOverlap(.overlap) } }
                        .accessibilityIdentifier("calendar.overlap.overlap")
                    Button("Cancel") { Task { await model.resolveOverlap(.cancel) } }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
        }
    }
}

/// The block popover: range, items, secondaries, suggestion, actions (§3.2).
struct BlockPopover: View {
    var model: CalendarModel
    var block: ActivityBlock
    @State private var candidates: [SuggestionCandidate] = []
    @State private var showsOthers = false

    var body: some View {
        let zone = model.calendar.timeZone
        let span = Int(block.end.timeIntervalSince(block.start))
        VStack(alignment: .leading, spacing: 8) {
            Text("\(CalendarText.range(block.start, block.end, zone: zone)) · \(ActivityText.duration(span)) · \(block.device)")
                .font(.headline)
            if block.activeSeconds < span {
                Text("\(ActivityText.duration(span)), \(ActivityText.duration(block.activeSeconds)) active").foregroundStyle(.secondary)
            }
            if block.source == .knowledge {
                Text("reconstructed").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.context).bold()
                    Text([item.subject, item.detail].filter { !$0.isEmpty }.joined(separator: " ")).lineLimit(1)
                    Spacer()
                    Text(ActivityText.duration(item.seconds))
                }
                .font(.caption)
            }
            ForEach(Array(block.background.enumerated()), id: \.offset) { _, item in
                Text("+ \(item.context) \(item.subject) (busy \(ActivityText.duration(item.seconds)))").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            suggestion
            HStack {
                Button("Create Entry…") { Task { await model.createEntry(from: block) } }
                if block.isOpen {
                    Button("Start Now") { Task { await model.startNow(block) } }
                }
            }
        }
        .padding()
        .frame(width: 340)
        .task { candidates = await model.suggestions(for: block) }
    }

    @ViewBuilder private var suggestion: some View {
        Text("Suggested").font(.caption).foregroundStyle(.secondary)
        if let top = candidates.first, top.isConfident {
            HStack {
                Text(CandidateText.title(top, model: model))
                Spacer()
                ConfidenceMeter(candidate: top)
                Button("Log") { Task { await model.log(block) } }
                    .accessibilityIdentifier("calendar.block.log")
            }
            DisclosureGroup("Other suggestions", isExpanded: $showsOthers) {
                ForEach(Array(candidates.dropFirst().prefix(2).enumerated()), id: \.offset) { _, candidate in
                    HStack {
                        Text(CandidateText.title(candidate, model: model))
                        Spacer()
                        ConfidenceMeter(candidate: candidate)
                    }
                }
            }
            .font(.caption)
        } else {
            Text("No confident suggestion").foregroundStyle(.secondary)
        }
    }
}

/// The time-block editor: title, project, start, end, notes; Delete for existing blocks.
struct TimeBlockEditor: View {
    @Bindable var model: CalendarModel
    @State private var showsPicker = false

    var body: some View {
        if let draft = model.blockDraft {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: Binding { model.blockDraft?.title ?? "" } set: { model.blockDraft?.title = $0 })
                    .accessibilityIdentifier("calendar.block.title")
                Button(model.project(draft.projectID)?.name ?? "No project") { showsPicker = true }
                    .popover(isPresented: $showsPicker) { picker(draft) }
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
                    Button("Save") { Task { await model.saveTimeBlock() } }.keyboardShortcut(.defaultAction)
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
