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
        return TextField("Filter", text: $list.filter, prompt: Text("Filter by task, project, or client"))
            .textFieldStyle(.roundedBorder)
            .focused($filterFocused)
            .padding(.horizontal, Design.Spacing.window)
            .padding(.vertical, Design.Spacing.small)
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
                        .padding(Design.Spacing.large)
                        .accessibilityIdentifier("timer.loadMore")
                    }
                }
                .padding(.horizontal, Design.Spacing.medium)
                .padding(.bottom, Design.Spacing.medium)
            }
            .overlay { emptyState }
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

    /// No entries yet, or none matching the filter.
    @ViewBuilder private var emptyState: some View {
        if app.list.days.isEmpty {
            if app.list.filter.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "stopwatch",
                    description: Text("Entries you track appear here by day.")
                )
            } else {
                ContentUnavailableView.search(text: app.list.filter)
            }
        }
    }
}

/// One day: header with title and total, then its rows.
private struct DaySection: View {
    @Environment(AppModel.self) private var app
    var day: TimerListDay

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(app.list.title(for: day.day))
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(DurationText.clock(day.totalSeconds(at: app.clock.now)))
                    .monospacedDigit()
                    .accessibilityIdentifier("timer.dayTotal.\(day.day)")
            }
        }
        .font(.headline)
        .padding(.leading, Design.Spacing.small)
        // The trailing edge lines up with the rows' durations.
        .padding(.trailing, Design.CircleDiameter.row + 2 * Design.Spacing.small)
        .padding(.top, Design.Spacing.large)
        .padding(.bottom, Design.Spacing.tight)
        .accessibilityIdentifier("timer.day.\(day.day)")
        if let running = day.runningListing {
            RunningRowView(listing: running)
        }
        ForEach(day.rows) { listing in
            EntryRowView(listing: listing)
        }
    }
}

/// The running entry as Today's first row: its live duration in the accent
/// color, no continue button; a click opens its edit popover on the bar.
private struct RunningRowView: View {
    @Environment(AppModel.self) private var app
    var listing: EntryListing
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Design.Spacing.small) {
            EntryRowLabels(listing: listing)
            Spacer(minLength: Design.Spacing.small)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(DurationText.clock(listing.entry.seconds(at: app.clock.now)))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }
            Color.clear.frame(width: Design.CircleDiameter.row, height: 1)
        }
        .padding(.vertical, Design.Spacing.small)
        .padding(.horizontal, Design.Spacing.small)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small)
            .fill(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Running since \(listing.entry.start.formatted(date: .omitted, time: .shortened))")
        .onTapGesture { app.presentation.editing = listing.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue("running")
        .accessibilityIdentifier("timer.runningRow")
    }
}

/// A row: task, project line, duration, and the continue button on hover
/// and selection.
struct EntryRowView: View {
    @Environment(AppModel.self) private var app
    var listing: EntryListing
    @State private var hovering = false
    @State private var editor: EntryEditorModel?

    var body: some View {
        let entry = listing.entry
        let selected = app.list.selection == entry.id
        HStack(spacing: Design.Spacing.small) {
            EntryRowLabels(listing: listing)
            Spacer(minLength: Design.Spacing.small)
            Text(DurationText.clock(entry.seconds(at: app.clock.now))).monospacedDigit()
            ZStack {
                if hovering || selected {
                    Button {
                        Task { await app.timer.continueEntry(entry.id) }
                    } label: {
                        Label("Continue", systemImage: "play.fill")
                    }
                    .buttonStyle(CircleButtonStyle(color: .startTint, diameter: Design.CircleDiameter.row))
                    .help("Continue")
                    .accessibilityIdentifier("timer.row.continue")
                }
            }
            .frame(width: Design.CircleDiameter.row)
        }
        .padding(.vertical, Design.Spacing.small)
        .padding(.horizontal, Design.Spacing.small)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(rowFill(selected: selected)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(Self.range(entry))
        .onTapGesture(count: 2) {
            app.rowDoubleClicked(entry.id)
        }
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            app.rowClicked(entry.id)
        }
        .contextMenu {
            ForEach(TimerRowMenuItem.allCases, id: \.self) { item in
                Button(item.title) { app.performRowMenu(item, on: entry.id) }
            }
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

    private func rowFill(selected: Bool) -> AnyShapeStyle {
        if selected {
            AnyShapeStyle(.fill.secondary)
        } else if hovering {
            AnyShapeStyle(.fill.quaternary)
        } else {
            AnyShapeStyle(.clear)
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
