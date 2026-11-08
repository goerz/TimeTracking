// ActivityModel: the Activity section's app filter, device, workspace view,
// and drill-downs (activity.md). Every figure comes from the library's
// `ActivitySummary`; this model holds selection and requests.

import Foundation
import Observation
import os
import TimeTrackingCore

/// The Activity section (read-only over the logs).
@Observable
final class ActivityModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let device: DeviceSettings
    @ObservationIgnored let activity: any ActivityReading
    @ObservationIgnored weak var router: SectionRouter?
    /// The agent's registration (Mac), for the footer's dot.
    @ObservationIgnored var registration: () async -> AgentRegistration = { .notRegistered }
    /// Whether the tracker is enabled with Accessibility (the setup card's rule).
    @ObservationIgnored var trackerSetUp: () async -> Bool = { false }
    /// The Macs' `LiveState` activity (iPad footer).
    @ObservationIgnored var remoteActivity: () async -> LiveState.MacActivity? = { nil }
    /// Whether this device shows the open block and the exclusion shortcuts (the iPad doesn't).
    @ObservationIgnored var isMac = true
    /// Whether today's date file has not arrived (iPad).
    @ObservationIgnored var waitingForICloud: () async -> Bool = { false }

    let range: DateRangeModel
    /// The selected apps; empty is All.
    private(set) var apps: Set<String> = []
    /// The "All devices" popup.
    var selectedDevice: String? {
        didSet {
            if oldValue != selectedDevice {
                Task { await reload() }
            }
        }
    }

    var workspaceKind: ActivityWorkspaceKind = .all
    /// The workspace whose items replace the list.
    private(set) var drill: ActivityWorkspaceRow?
    var moreSearch = ""
    var showsMore = false
    var showsAllApps = false
    var showsAllWorkspaces = false
    /// The date popover, also opened by View › Date Range… (⇧⌘D).
    var showsDatePopover = false
    /// The heatmap cell the arrow keys stand on.
    var focusedCell: ActivityHeatmap.Cell?
    /// The bar or segment the arrow keys stand on.
    var focusedBar: ActivityBars.Target?
    /// Space: the focused cell's details under the heatmap.
    var showsCellDetails = false
    /// Space: the focused bar's or segment's tooltip over the chart.
    var showsBarDetails = false

    private(set) var summary: ActivitySummary?
    private(set) var health: ActivityHealth?
    private(set) var emptyState: ActivityEmptyState = .panels
    private(set) var appColors: [String: Int] = [:]
    private(set) var isLoading = false
    /// "Waiting for iCloud" (iPad), with the newest activity's end.
    private(set) var iCloudWaiting = false
    private(set) var newestBlockEnd: Date?
    /// The range revision the figures belong to; arrows keep the filter.
    @ObservationIgnored private var seenRevision = -1
    /// Counts reloads; only the latest one assigns its results.
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var arrowRevision = -1

    init(store: TimeStore, clock: any Clock, device: DeviceSettings, activity: any ActivityReading, range: DateRangeModel) {
        self.store = store
        self.clock = clock
        self.device = device
        self.activity = activity
        self.range = range
    }

    /// The shown days (at most 366) and whether the selection was clipped.
    var days: ClosedRange<TrackingDay> {
        range.activityDays.days
    }

    /// "Showing the last 366 days of the selection".
    var clipNote: String? {
        range.activityDays.clipped ? "Showing the last 366 days of the selection" : nil
    }

    // MARK: Loading

    /// Reads the blocks of the range and builds the summary off the main
    /// thread, keeping the previous figures until it is ready. A reload
    /// started later wins: an earlier one that finishes after it changes
    /// nothing (a long range read can outlast a short one).
    func reload() async {
        if range.revision != seenRevision, range.revision != arrowRevision, seenRevision >= 0 {
            apps = []
            drill = nil
        }
        seenRevision = range.revision
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            range.refreshCalendar(store)
            let days = days
            let interval = range.calendar.interval(of: days)
            let hour = range.calendar.startOfDayHour
            let loaded = try await activity.blocks(in: interval, devices: nil)
            // Only the recording Mac shows the open block.
            let blocks = isMac ? loaded : loaded.filter { !$0.isOpen }
            let newest = blocks.map(\.end).max()
            let input = try await ActivitySummaryInput(
                blocks: blocks,
                backgroundBlocks: activity.backgroundBlocks(in: interval, devices: nil),
                days: days,
                today: range.today,
                apps: apps,
                device: selectedDevice,
                startOfDayHour: hour,
                settings: activity.settings,
                exclusions: activity.exclusions
            )
            let summary = await Task.detached { ActivitySummary(input) }.value
            guard generation == loadGeneration else {
                return
            }
            newestBlockEnd = newest
            self.summary = summary
            if summary.hasBlocks {
                device[.activitySawBlock] = true
            }
            await loadHealth()
            let emptyState = await ActivityEmptyState.resolve(
                summary: summary,
                everSawBlock: device[.activitySawBlock],
                trackerSetUp: trackerSetUp(),
                footerRed: health?.isRed ?? false
            )
            guard generation == loadGeneration else {
                return
            }
            self.emptyState = emptyState
            if let assigned = try? await store.assignAppColors(summary.ranking.map(\.app)), generation == loadGeneration {
                appColors = assigned
            }
        } catch {
            Logging.logger(category: "Sections").error("Activity: \(String(describing: error), privacy: .public)")
        }
    }

    /// The footer's re-read period while visible (§1.10).
    static let healthRefreshInterval: Duration = .seconds(10)

    /// While the footer is visible: reads the health now and after every
    /// `healthRefreshInterval`, until the task is cancelled. `sleep` is the
    /// tests' seam.
    func followHealth(sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async {
        while !Task.isCancelled {
            await loadHealth()
            do {
                try await sleep(Self.healthRefreshInterval)
            } catch {
                return
            }
        }
    }

    /// The footer's dot, status line, and sources.
    func loadHealth() async {
        if isMac {
            health = await ActivityHealth(registration: registration(), state: activity.currentState(), now: clock.now)
        } else {
            iCloudWaiting = await waitingForICloud()
            health = await remoteActivity().map { ActivityHealth(remote: $0, now: clock.now) }
        }
    }

    /// The color index of an app.
    func colorIndex(_ app: String) -> Int? {
        appColors[app]
    }

    // MARK: Filter (§1.3)

    /// A chip or an Apps row: toggles the app.
    func toggle(_ app: String) async {
        apps.formSymmetricDifference([app])
        filterChanged()
        await reload()
    }

    /// "All" clears the filter.
    func selectAll() async {
        apps = []
        filterChanged()
        await reload()
    }

    /// "Show Only <name>".
    func showOnly(_ app: String) async {
        apps = [app]
        filterChanged()
        await reload()
    }

    /// Sites when every selected app is a browser, else All (§1.6).
    private func filterChanged() {
        let kinds = (summary?.ranking ?? []).filter { apps.contains($0.app) }.map(\.kind)
        workspaceKind = apps.isEmpty ? .all : ActivityWorkspaceKind.automatic(for: kinds)
        drill = nil
    }

    /// The main window reopened: the filter resets.
    func mainWindowReopened() {
        apps = []
        drill = nil
        workspaceKind = .all
    }

    /// ⌥⌘← / ⌥⌘→ and the arrows keep the filter.
    func shiftPeriod(by step: Int) async {
        if step < 0 {
            range.previous()
        } else {
            range.next()
        }
        arrowRevision = range.revision
        await reload()
    }

    /// Escape: leaves a workspace drill-down, else clears the filter.
    func escape() async {
        if drill != nil {
            drill = nil
        } else if !apps.isEmpty {
            await selectAll()
        }
    }

    // MARK: Workspaces (§1.6)

    var workspaceRows: [ActivityWorkspaceRow] {
        (summary?.workspaceRows ?? []).filter { $0.matches(workspaceKind) }
    }

    /// The chevron of a row with items lists them, on every device.
    func open(_ row: ActivityWorkspaceRow) {
        guard row.hasItems else {
            return
        }
        drill = row
    }

    func closeDrill() {
        drill = nil
    }

    /// "WezTerm › MyApp": the drilled workspace's app and name.
    var drillBreadcrumb: String? {
        drill.map { row in
            let app = row.apps.first(where: apps.contains) ?? row.apps.first
            return [app, row.name].compactMap(\.self).joined(separator: " › ")
        }
    }

    // MARK: Drill-down into the Calendar (§3)

    /// A heatmap cell: that day (a week or month row's first day) at its hour.
    func showInCalendar(row: ActivityHeatmap.Row, hour: Int) {
        guard let day = row.days.first else {
            return
        }
        router?.showCalendar(day: day, hour: hour, highlight: .hour(hour))
    }

    /// A bar (no hour) or a segment (its app highlighted).
    func showInCalendar(_ target: ActivityBars.Target, in bars: ActivityBars) {
        guard let day = bars.bar(of: target)?.days.first else {
            return
        }
        var highlight: BlockHighlight?
        if case let .app(app) = target.series {
            highlight = .app(app)
        }
        router?.showCalendar(day: day, hour: nil, highlight: highlight)
    }

    /// "Show in Calendar" on an Apps row: the range's first day, its blocks highlighted.
    func showAppInCalendar(_ app: String) {
        router?.showCalendar(day: days.lowerBound, hour: nil, highlight: .app(app))
    }

    // MARK: Exclusions (§4)

    /// "Exclude <name> from Tracking…" for an app (browsers are excluded per site).
    func exclude(app: String) {
        guard let total = summary?.ranking.first(where: { $0.app == app }),
              let draft = TrackerExclusionDraft.forApp(appID: total.appID, kind: total.kind)
        else {
            return
        }
        router?.showTrackerSettings(exclusion: draft)
    }

    /// "Exclude <name> from Tracking…" for a folder or site row.
    func exclude(workspace row: ActivityWorkspaceRow) {
        guard let draft = TrackerExclusionDraft.forWorkspace(row) else {
            return
        }
        router?.showTrackerSettings(exclusion: draft)
    }
}
