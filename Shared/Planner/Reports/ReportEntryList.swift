// ReportEntryList: one row per matching entry, sortable, with the Timer
// window's edit popover (spec_planner_reports.md §6).

import SwiftUI
import TimeTrackingCore

/// The entry list with its footer.
struct ReportEntryList: View {
    @Bindable var model: ReportsModel

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            list
            Divider()
            TimelineView(.periodic(from: .now, by: model.listTicks ? 1 : 3600)) { _ in
                Text(model.listFooter(at: model.clock.now))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("reports.listFooter")
            }
        }
    }

    private var list: some View {
        List(selection: $model.listSelection) {
            ForEach(model.listings) { listing in
                ReportEntryRow(model: model, listing: listing).tag(listing.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: EntryID.self) { ids in
            if let id = ids.first, let listing = model.listings.first(where: { $0.id == id }) {
                Button("Edit…") { model.edit(id) }
                Button("Continue") { Task { await model.continueListing(id) } }
                Button("Show in Calendar") { model.showInCalendar(listing) }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                model.edit(id)
            }
        }
        .onKeyPress(.return) {
            if let id = model.listSelection.first {
                model.edit(id)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            Task { await model.clearEntryPath() }
            return .handled
        }
        .accessibilityIdentifier("reports.entries")
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            header("Date", .date, width: 80)
            header("Start", .start, width: 70)
            header("Stop", .stop, width: 70)
            header("Duration", .duration, width: 100)
            header("Client", .client, width: 120)
            header("Project", .project, width: 180)
            header("Task", .task, width: nil)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func header(_ title: String, _ column: EntryListColumn, width: CGFloat?) -> some View {
        let button = Button {
            model.sortList(by: column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if model.state.listSort == column {
                    Image(systemName: model.state.listAscending ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        if let width {
            button.frame(width: width, alignment: .leading)
        } else {
            button.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One entry row; the running entry's duration counts up every second.
private struct ReportEntryRow: View {
    var model: ReportsModel
    var listing: EntryListing

    @State private var editor: EntryEditorModel?

    var body: some View {
        let entry = listing.entry
        HStack(spacing: 10) {
            Text(DayText.weekdayShortDate(entry.day)).frame(width: 80, alignment: .leading)
            Text(entry.start.formatted(date: .omitted, time: .shortened)).frame(width: 70, alignment: .leading)
            Text(entry.end?.formatted(date: .omitted, time: .shortened) ?? "running").frame(width: 70, alignment: .leading)
            TimelineView(.periodic(from: .now, by: entry.isRunning ? 1 : 3600)) { _ in
                HStack(spacing: 4) {
                    if entry.isRunning {
                        Image(systemName: "record.circle").foregroundStyle(.red).accessibilityLabel("Running")
                    }
                    Text(ReportText.seconds(entry.seconds(at: model.clock.now))).monospacedDigit()
                }
            }
            .frame(width: 100, alignment: .leading)
            Text(listing.client?.name ?? "–").frame(width: 120, alignment: .leading)
            HStack(spacing: 6) {
                if listing.project != nil {
                    AreaDot(color: listing.area?.color)
                }
                Text(listing.project?.name ?? "–")
            }
            .frame(width: 180, alignment: .leading)
            Text(entry.task).lineLimit(1).truncationMode(.tail).help(entry.task)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reports.entry")
        .popover(isPresented: editingBinding, arrowEdge: .leading) {
            if let editor {
                EntryEditorView(model: editor, makePicker: makePicker) {
                    model.editing = nil
                }
            }
        }
        .onChange(of: model.editing, initial: true) { _, editing in
            if editing == listing.id {
                let editor = EntryEditorModel(store: model.store, clock: model.clock, entry: listing.entry)
                editor.onChange = { await model.editorChanged() }
                editor.onDelete = { model.editing = nil }
                self.editor = editor
            }
        }
    }

    private var editingBinding: Binding<Bool> {
        Binding {
            model.editing == listing.id && editor != nil
        } set: { shown in
            if !shown {
                model.editing = nil
            }
        }
    }

    private func makePicker(_ current: ProjectID?) -> ProjectPickerModel {
        ProjectPickerModel(store: model.store, currentProject: current, taskMatching: false)
    }
}
