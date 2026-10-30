// TimerListView: recent entries by day (spec_timer_window.md §3).

import SwiftUI
import TimeTrackingCore

/// The list: day headers with live totals, one row per entry, the filter,
/// and "Load Earlier Entries".
struct TimerListView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var listFocused: Bool
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if app.list.isFilterVisible {
                filterField
            }
            scrollingList
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onChange(of: listFocused) { _, focused in app.presentation.listFocused = focused }
                .onChange(of: app.presentation.focusListRequest) { listFocused = true }
                .onKeyPress(.upArrow) {
                    app.list.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    app.list.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    app.presentation.editing = app.list.selection
                    return .handled
                }
                .onKeyPress(.escape) {
                    app.list.clearSelection()
                    return .handled
                }
                .accessibilityIdentifier("timer.list")
        }
    }

    /// ⌘F's filter field; Escape clears and hides it.
    private var filterField: some View {
        @Bindable var list = app.list
        return TextField("Filter", text: $list.filter)
            .textFieldStyle(.roundedBorder)
            .focused($filterFocused)
            .padding(8)
            .accessibilityIdentifier("timer.filterField")
            .onAppear { filterFocused = true }
            .onChange(of: list.filter) { Task { await app.list.reload() } }
            .onKeyPress(.escape) {
                Task { await app.list.hideFilter() }
                return .handled
            }
    }

    private var scrollingList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    ForEach(app.list.days) { day in
                        DaySection(day: day)
                    }
                    if app.list.canLoadMore {
                        Button("Load Earlier Entries") {
                            Task { await app.list.loadMore() }
                        }
                        .buttonStyle(.link)
                        .padding(16)
                        .accessibilityIdentifier("timer.loadMore")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: app.list.scrollToTopRequest) {
                proxy.scrollTo("top", anchor: .top)
            }
            .onChange(of: app.list.selection) { _, selection in
                if let selection {
                    proxy.scrollTo(selection)
                }
            }
        }
    }
}

/// One day: header with title and total, then its rows.
private struct DaySection: View {
    @Environment(AppModel.self) private var app
    var day: TimerListDay

    var body: some View {
        HStack {
            Text(app.list.title(for: day.day)).font(.headline)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(DurationText.clock(day.totalSeconds(at: app.clock.now)))
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("timer.dayTotal.\(day.day)")
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
        .accessibilityIdentifier("timer.day.\(day.day)")
        ForEach(day.rows) { listing in
            EntryRowView(listing: listing)
            if listing.id != day.rows.last?.id {
                Divider()
            }
        }
    }
}

/// A row: task, project line, duration, and the continue button on hover.
struct EntryRowView: View {
    @Environment(AppModel.self) private var app
    var listing: EntryListing
    @State private var hovering = false
    @State private var editor: EntryEditorModel?

    var body: some View {
        let entry = listing.entry
        let label = ProjectLabel(listing)
        let selected = app.list.selection == entry.id
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.task.isEmpty ? "No task" : entry.task)
                    .foregroundStyle(entry.task.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    AreaDot(color: label.color)
                    Text(label.name).lineLimit(1)
                    if let client = label.client {
                        Text("· \(client)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.callout)
            }
            Spacer()
            Text(DurationText.clock(entry.seconds(at: app.clock.now))).monospacedDigit()
            if hovering {
                Button {
                    Task { await app.timer.continueEntry(entry.id) }
                } label: {
                    Label("Continue", systemImage: "play.fill").labelStyle(.iconOnly)
                }
                .buttonStyle(CircleButtonStyle(color: .startGreen, diameter: 26))
                .help("Continue")
                .accessibilityIdentifier("timer.row.continue")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected || hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(Self.range(entry))
        .onTapGesture(count: 2) {
            Task { await app.timer.continueEntry(entry.id) }
        }
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            app.list.selection = entry.id
            app.presentation.editing = entry.id
        }
        .contextMenu {
            Button("Continue") { Task { await app.timer.continueEntry(entry.id) } }
            Button("Edit…") {
                app.list.selection = entry.id
                app.presentation.editing = entry.id
            }
            Button("Delete…") { app.timer.alert = app.list.deleteAlert(for: entry.id) }
        }
        .id(entry.id)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timer.row")
        .accessibilityValue(selected ? "selected" : "")
        .popover(isPresented: editingBinding, arrowEdge: .leading) {
            if let editor {
                EntryEditorView(model: editor, makePicker: makePicker) {
                    app.presentation.editing = nil
                }
            }
        }
        .onChange(of: app.presentation.editing) { _, editing in
            if editing == entry.id {
                editor = makeEditor()
            }
        }
    }

    private var editingBinding: Binding<Bool> {
        Binding {
            app.presentation.editing == listing.id && editor != nil
        } set: { shown in
            if !shown, app.presentation.editing == listing.id {
                app.presentation.editing = nil
            }
        }
    }

    private func makeEditor() -> EntryEditorModel {
        let model = EntryEditorModel(store: app.store, clock: app.clock, entry: listing.entry)
        model.onChange = { await app.afterChange() }
        model.onDelete = { app.presentation.editing = nil }
        return model
    }

    private func makePicker(_ current: ProjectID?) -> ProjectPickerModel {
        ProjectPickerModel(store: app.store, currentProject: current, taskMatching: false)
    }

    /// "9:10 to 9:35".
    static func range(_ entry: TimeEntry) -> String {
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        let end = entry.end.map { $0.formatted(date: .omitted, time: .shortened) } ?? "now"
        return "\(start) to \(end)"
    }
}
