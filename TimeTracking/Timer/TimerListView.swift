// TimerListView: recent entries by day (spec_timer.md §3).

import SwiftUI
import TimeTrackingCore

/// The list: day headers with live totals, one row per entry, the filter,
/// and "Load Earlier Entries".
struct TimerListView: View {
    @Environment(AppModel.self) private var app
    @Environment(TimerUIState.self) private var view
    @FocusState private var listFocused: Bool
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if view.list.isFilterVisible {
                filterField
            }
            scrollingList
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onChange(of: listFocused) { _, focused in view.listFocused = focused }
                .onChange(of: view.focusListRequest) { listFocused = true }
                .onKeyPress(.upArrow) {
                    view.list.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    view.list.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    view.editing = view.list.selection
                    return .handled
                }
                .onKeyPress(.escape) {
                    view.list.clearSelection()
                    return .handled
                }
                .accessibilityIdentifier("timer.list")
        }
        .onChange(of: view.list.filterFocusRequests) {
            // A field that has just appeared takes no focus yet.
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                filterFocused = true
            }
        }
    }

    /// ⌘F's filter field; Escape clears and hides it.
    private var filterField: some View {
        @Bindable var list = view.list
        return TextField("Filter", text: $list.filter, prompt: Text("Filter by task, project, or client"))
            .textFieldStyle(.roundedBorder)
            .focused($filterFocused)
            .padding(.horizontal, Design.Spacing.window)
            .padding(.vertical, Design.Spacing.small)
            .accessibilityIdentifier("timer.filterField")
            .onChange(of: list.filter) { Task { await view.list.reload() } }
            .onKeyPress(.escape) {
                Task { await view.list.hideFilter() }
                return .handled
            }
    }

    private var scrollingList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    ForEach(view.list.days) { day in
                        DaySection(day: day)
                    }
                    if view.list.canLoadMore {
                        Button("Load Earlier Entries") {
                            Task { await view.list.loadMore() }
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
            .onChange(of: view.list.scrollToTopRequest) {
                proxy.scrollTo("top", anchor: .top)
            }
            .onChange(of: view.list.selection) { _, selection in
                if let selection {
                    proxy.scrollTo(selection)
                }
            }
        }
    }

    /// No entries yet, or none matching the filter.
    @ViewBuilder private var emptyState: some View {
        if view.list.days.isEmpty {
            if view.list.filter.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: SymbolName.timer,
                    description: Text("Entries you track appear here by day.")
                )
            } else {
                ContentUnavailableView.search(text: view.list.filter)
            }
        }
    }
}

/// One day: header with title and total, then its rows.
private struct DaySection: View {
    @Environment(AppModel.self) private var app
    @Environment(TimerUIState.self) private var view
    var day: TimerListDay

    var body: some View {
        DayHeaderLabel(day: day, title: view.list.title(for: day.day), clock: app.clock)
            .font(.headline)
            .padding(.leading, Design.Spacing.small)
            // The trailing edge lines up with the rows' durations.
            .padding(.trailing, Design.CircleDiameter.row + 2 * Design.Spacing.small)
            .padding(.top, Design.Spacing.large)
            .padding(.bottom, Design.Spacing.tight)
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
    @Environment(TimerUIState.self) private var view
    var listing: EntryListing
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Design.Spacing.small) {
            EntryRowLabels(listing: listing)
            Spacer(minLength: Design.Spacing.small)
            RunningDurationText(entry: listing.entry, clock: app.clock)
            Color.clear.frame(width: Design.CircleDiameter.row, height: 1)
        }
        .padding(.vertical, Design.Spacing.small)
        .padding(.horizontal, Design.Spacing.small)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small)
            .fill(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Running since \(listing.entry.start.formatted(date: .omitted, time: .shortened))")
        .onTapGesture { app.editRunningEntry(in: view) }
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
    @Environment(TimerUIState.self) private var view
    var listing: EntryListing
    @State private var hovering = false

    var body: some View {
        let entry = listing.entry
        let selected = view.list.selection == entry.id
        HStack(spacing: Design.Spacing.small) {
            EntryRowLabels(listing: listing)
            Spacer(minLength: Design.Spacing.small)
            Text(DurationText.clock(entry.seconds(at: app.clock.now))).monospacedDigit()
            ZStack {
                if hovering || selected {
                    Button {
                        Task { await app.timer.continueEntry(entry.id) }
                    } label: {
                        Label("Continue", systemImage: SymbolName.start)
                    }
                    .buttonStyle(CircleButtonStyle(color: .startTint, diameter: Design.CircleDiameter.row))
                    .help("Continue")
                    .accessibilityIdentifier("timer.row.continue.\(entry.id)")
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
            app.rowClicked(entry.id, in: view)
        }
        .contextMenu {
            ForEach(TimerRowMenuItem.allCases, id: \.self) { item in
                Button(item.title) { app.performRowMenu(item, on: entry.id, in: view) }
            }
        }
        .id(entry.id)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timer.row.\(entry.id)")
        .accessibilityValue(selected ? "selected" : "")
        .modifier(EntryEditorPopover(
            entry: listing.editable,
            editing: Bindable(view).editing,
            store: app.store,
            clock: app.clock,
            arrowEdge: .leading
        ) { await app.afterChange() })
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

    /// "9:10 to 9:35".
    static func range(_ entry: TimeEntry) -> String {
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        let end = entry.end.map { $0.formatted(date: .omitted, time: .shortened) } ?? "now"
        return "\(start) to \(end)"
    }
}
