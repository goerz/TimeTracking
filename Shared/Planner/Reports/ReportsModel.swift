// ReportsModel: the Reports section's view state and commands
// (spec_planner_reports.md). Every figure comes from the library's
// `ReportSnapshot`; this model holds selection, expansion, and sorts.

import Foundation
import Observation
import os
import TimeTrackingCore

/// One visible row of the breakdown table.
struct BreakdownRow: Identifiable, Equatable {
    var path: [GroupKeyValue]
    var node: ReportNode
    var level: GroupKey
    var depth: Int
    var isExpanded: Bool

    var id: [GroupKeyValue] {
        path
    }

    var hasChildren: Bool {
        !node.children.isEmpty
    }

    /// "Research (3)" for nodes with children; "(archived)" for archived projects.
    var title: String {
        var name = node.displayName(level: level)
        if node.isArchived {
            name += " (archived)"
        }
        return name
    }
}

/// State and commands of the Reports section.
@Observable
final class ReportsModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let device: DeviceSettings
    @ObservationIgnored weak var router: PlannerRouter?
    /// The Timer's continue command.
    @ObservationIgnored var continueEntry: (EntryID) async -> Void = { _ in }
    /// Called after an edit through the entry editor (the Timer re-reads).
    @ObservationIgnored var entriesChanged: () async -> Void = {}
    let range: DateRangeModel

    var state: ReportViewState {
        didSet { device[.reportsState] = state }
    }

    private(set) var snapshot: ReportSnapshot?
    /// A reload is running (the toolbar's progress bar after 250 ms).
    private(set) var isLoading = false
    /// The running entry's day lies in the range.
    private(set) var runningInRange = false
    /// Expanded key paths for this session; reset when the levels change.
    var expanded: Set<[GroupKeyValue]> = []
    var expansionInitialized = false
    /// A breakdown node narrowing the entry list (the chip).
    var entryPath: [GroupKeyValue] = []
    /// The range before a drill-down, one level deep (⌘[).
    private(set) var previousRange: ReportRange?
    /// The legend entry that dims the others.
    var highlightedKey: GroupKeyValue?
    /// The hovered bar.
    var hoveredBucket: TrackingDay?
    var tableSelection: Set<[GroupKeyValue]> = []
    var listSelection: Set<EntryID> = []
    /// The entry whose edit popover is open.
    var editing: EntryID?
    /// Bumped to focus the Task filter (⌘F) or open the popovers.
    private(set) var taskFocusRequests = 0
    var showsFilters = false
    /// File › Export… asks for the format first.
    var exportRequested = false
    var showsDatePopover = false
    private(set) var clients: [Client] = []
    private(set) var areas: [Area] = []
    private(set) var projects: [ProjectRow] = []
    private(set) var lastError: String?
    private var loadGeneration = 0

    init(store: TimeStore, clock: any Clock, device: DeviceSettings, range: DateRangeModel) {
        self.store = store
        self.clock = clock
        self.device = device
        self.range = range
        self.state = device[.reportsState]
    }

    // MARK: Loading

    /// The snapshot's request.
    var request: ReportRequest {
        ReportRequest(
            days: range.days,
            today: range.today,
            levels: state.levels,
            granularity: state.granularity,
            stack: state.stack,
            filter: state.filters.entryFilter,
            entryPath: entryPath,
            includeEntries: true
        )
    }

    /// Recomputes; the previous result stays until the new one is ready.
    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        await range.refreshEarliest(store)
        do {
            clients = try await store.clients(includeRetired: true)
            areas = try await store.areas(of: nil, includeRetired: true)
            projects = try await store.projects(filter: ProjectFilter(state: .all))
            let normalized = state.filters.normalized(clients: clients, areas: areas, projects: projects)
            if normalized != state.filters {
                state.filters = normalized
            }
            let result = try await store.reportSnapshot(request)
            let running = try await store.runningEntry()
            guard generation == loadGeneration else {
                return
            }
            snapshot = result
            runningInRange = running.map { range.days.contains($0.day) } ?? false
            initializeExpansion()
        } catch {
            report(error)
        }
        if generation == loadGeneration {
            isLoading = false
        }
    }

    /// While the running entry is in the range: every 60 s for tiles, chart,
    /// and table (the list's running row counts each second in the view).
    var refreshInterval: Duration? {
        runningInRange ? .seconds(60) : nil
    }

    /// Whether the list's running row ticks every second.
    var listTicks: Bool {
        runningInRange && state.card == .entries
    }

    private func initializeExpansion() {
        guard !expansionInitialized, let tree = snapshot?.tree else {
            return
        }
        expansionInitialized = true
        if tree.children.count == 1, let only = tree.children.first, !only.children.isEmpty {
            expanded.insert([only.key])
        }
    }

    // MARK: Range

    func previousPeriod() async {
        range.previous()
        await reload()
    }

    func nextPeriod() async {
        range.next()
        await reload()
    }

    func goToToday() async {
        range.goToToday()
        await reload()
    }

    /// Double-click on a bar: that bucket becomes the range.
    func drillDown(_ bucket: ChartBucket) async {
        previousRange = range.range
        range.set(.days(bucket.days.lowerBound, bucket.days.upperBound))
        await reload()
    }

    /// ⌘[ after a drill-down; a second one does nothing.
    func backToPreviousRange() async {
        guard let previous = previousRange else {
            return
        }
        previousRange = nil
        range.set(previous)
        await reload()
    }

    /// `showReports(range:filter:)`: the range, exactly these filters with
    /// archived projects included, and the Breakdown.
    func show(range newRange: ReportRange?, filters: ReportFilters) async {
        if let newRange {
            range.set(newRange)
        }
        var filters = filters
        filters.includeArchived = true
        state.filters = filters
        state.card = .breakdown
        entryPath = []
        await reload()
    }

    // MARK: Filters

    var filterChips: [ReportFilterChip] {
        state.filters.chips(clients: clients, areas: areas, projects: projects)
    }

    func removeChip(_ kind: ReportFilterChip.Kind) async {
        state.filters.remove(kind)
        await reload()
    }

    /// ⌥⇧⌘F and "Clear All".
    func clearFilters() async {
        state.filters = ReportFilters()
        await reload()
    }

    func setFilters(_ filters: ReportFilters) async {
        state.filters = filters
        await reload()
    }

    /// ⌘F: focus in the Task filter.
    func focusTaskFilter() {
        showsFilters = true
        taskFocusRequests += 1
    }

    // MARK: Chart

    func setGranularity(_ granularity: Granularity?) async {
        state.granularity = granularity
        await reload()
    }

    func setStack(_ stack: StackKind) async {
        state.stack = stack
        highlightedKey = nil
        await reload()
    }

    /// A legend click dims the other keys until clicked again.
    func toggleHighlight(_ key: GroupKeyValue) {
        highlightedKey = highlightedKey == key ? nil : key
    }

    // MARK: Levels

    /// The kinds a level popup offers: unused ones and its own.
    func availableKinds(at index: Int) -> [GroupKey] {
        GroupKey.allCases.filter { !state.levels.contains($0) || state.levels.indices.contains(index) && state.levels[index] == $0 }
    }

    var canAddLevel: Bool {
        state.levels.count < 4
    }

    func setLevel(_ index: Int, to kind: GroupKey) async {
        guard state.levels.indices.contains(index), !state.levels.contains(kind) else {
            return
        }
        state.levels[index] = kind
        await levelsChanged()
    }

    /// "+": the first unused kind.
    func addLevel() async {
        guard canAddLevel, let kind = GroupKey.allCases.first(where: { !state.levels.contains($0) }) else {
            return
        }
        state.levels.append(kind)
        await levelsChanged()
    }

    /// "Remove Level", not on the first.
    func removeLevel(_ index: Int) async {
        guard index > 0, state.levels.indices.contains(index) else {
            return
        }
        state.levels.remove(at: index)
        await levelsChanged()
    }

    func levelsChanged() async {
        expanded = []
        expansionInitialized = false
        entryPath = []
        await reload()
    }

    private func report(_ error: any Error) {
        lastError = UserMessage.text(for: error)
        Logging.logger(category: "Planner").error("Reports failed: \(String(describing: error), privacy: .public)")
    }
}
