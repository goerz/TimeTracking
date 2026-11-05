// ActivityModel: the Activity section's filter, device, subject view, and
// drill-downs (spec_activity.md). Every figure comes from the
// library's `ActivitySummary`; this model holds selection and requests.

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
    /// The app name of a bundle identifier (Mac: installed apps).
    @ObservationIgnored var appName: (String) -> String? = { _ in nil }
    @ObservationIgnored var isRecordingMac = true
    /// Whether the current month's block file has not arrived (iPad).
    @ObservationIgnored var waitingForICloud: () async -> Bool = { false }
    @ObservationIgnored var homeDirectory = NSHomeDirectory()

    let range: DateRangeModel
    /// The selected contexts; empty is All.
    private(set) var contexts: Set<String> = []
    /// The "All devices" popup.
    var selectedDevice: String? {
        didSet {
            if oldValue != selectedDevice {
                Task { await reload() }
            }
        }
    }

    var subjectKind: ActivitySubjectKind = .all
    /// The subject whose details replace the list.
    private(set) var drill: ActivitySubjectRow?
    var moreSearch = ""
    var showsMore = false
    var showsAllContexts = false
    var showsAllSubjects = false
    /// The date popover, also opened by View › Date Range… (⇧⌘D).
    var showsDatePopover = false
    /// The focused heatmap cell (row id, hour) for the arrow keys.
    var focusedCell: (row: Int, hour: Int)?

    private(set) var summary: ActivitySummary?
    private(set) var health: ActivityHealth?
    private(set) var emptyState: ActivityEmptyState = .panels
    private(set) var contextColors: [String: Int] = [:]
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
            contexts = []
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
            let hour = range.calendar.midnightHour
            let loaded = try await activity.blocks(in: interval, devices: nil)
            // Only the recording Mac shows the open block.
            let blocks = (isRecordingMac ? loaded : loaded.filter { !$0.isOpen }).map { $0.shown(midnightHour: hour) }
            let newest = blocks.map(\.end).max()
            let stretches = try await activity.backgroundStretches(in: interval, devices: nil).map { $0.shown(midnightHour: hour) }
            let details = isRecordingMac ? try await activity.details(for: blocks.map(\.id)) : [:]
            let input = ActivitySummaryInput(
                blocks: blocks,
                days: days,
                today: range.today,
                contexts: contexts,
                device: selectedDevice,
                details: details,
                idleClose: activity.idleClose,
                exclusions: activity.exclusions,
                stretches: stretches
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
            if let assigned = try? await store.assignContextColors(summary.ranking.map(\.context)), generation == loadGeneration {
                contextColors = assigned
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
        if isRecordingMac {
            health = await ActivityHealth(registration: registration(), state: activity.currentState(), now: clock.now)
        } else {
            iCloudWaiting = await waitingForICloud()
            health = await remoteActivity().map { ActivityHealth(remote: $0, now: clock.now) }
        }
    }

    /// The color index of a context (`nil`: gray).
    func colorIndex(_ context: String) -> Int? {
        ActivityContext(context).isPrivate ? nil : contextColors[context]
    }

    func displayName(_ context: String) -> String {
        ActivityContext(context).displayName(bundleIdentifier: activity.bundleIdentifier(forContext: context), appName: appName)
    }

    // MARK: Filter (§1.3)

    /// A chip or a Contexts row: toggles the context.
    func toggle(_ context: String) async {
        contexts.formSymmetricDifference([context])
        filterChanged()
        await reload()
    }

    /// "All" clears the filter.
    func selectAll() async {
        contexts = []
        filterChanged()
        await reload()
    }

    /// "Show Only <name>".
    func showOnly(_ context: String) async {
        contexts = [context]
        filterChanged()
        await reload()
    }

    private func filterChanged() {
        subjectKind = ActivitySubjectKind.automatic(for: contexts)
        drill = nil
    }

    /// The main window reopened: the filter resets.
    func mainWindowReopened() {
        contexts = []
        drill = nil
        subjectKind = .all
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

    /// Escape: leaves a subject drill-down, else clears the filter.
    func escape() async {
        if drill != nil {
            drill = nil
        } else if !contexts.isEmpty {
            await selectAll()
        }
    }

    // MARK: Subjects (§1.6)

    var subjectRows: [ActivitySubjectRow] {
        (summary?.subjectRows ?? []).filter { $0.matches(subjectKind) }
    }

    /// The chevron of a row with details (recording Mac only).
    func open(_ row: ActivitySubjectRow) {
        guard isRecordingMac, row.hasDetails else {
            return
        }
        drill = row
    }

    func closeDrill() {
        drill = nil
    }

    var drillDetail: ActivitySubjectDetail? {
        drill.flatMap { summary?.subjectDetail($0, homeDirectory: homeDirectory) }
    }

    // MARK: Drill-down into the Calendar (§3)

    /// A heatmap cell: that day (a week or month row's first day) at its hour.
    func showInCalendar(row: ActivityHeatmap.Row, hour: Int) {
        guard let day = row.days.first else {
            return
        }
        router?.showCalendar(day: day, hour: hour, highlight: .hour(hour))
    }

    /// A bar (no hour) or a segment (its context highlighted).
    func showInCalendar(bar: ActivityBars.Bar, series: ActivityBars.Series?) {
        guard let day = bar.days.first else {
            return
        }
        var highlight: BlockHighlight?
        if case let .context(context) = series {
            highlight = .context(context)
        }
        router?.showCalendar(day: day, hour: nil, highlight: highlight)
    }

    /// "Show in Calendar" on a context row: the range's first day, its blocks highlighted.
    func showContextInCalendar(_ context: String) {
        router?.showCalendar(day: days.lowerBound, hour: nil, highlight: .context(context))
    }

    // MARK: Exclusions (§4)

    /// "Exclude <name> from Tracking…" for a context (apps and sessions).
    func exclude(context: String) {
        guard let draft = TrackerExclusionDraft.forContext(context, bundleIdentifier: activity.bundleIdentifier(forContext: context)) else {
            return
        }
        router?.showTrackerSettings(exclusion: draft)
    }

    /// "Exclude <site> from Tracking…" for a site row.
    func exclude(site: String) {
        router?.showTrackerSettings(exclusion: .forSite(site))
    }
}
