// ActivityModel: the Activity section's filter, device, subject view, and
// drill-downs (spec_planner_activity.md). Every figure comes from the
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
    @ObservationIgnored weak var router: PlannerRouter?
    /// The agent's registration (Mac), for the footer's dot.
    @ObservationIgnored var registration: () async -> AgentRegistration = { .notRegistered }
    /// Whether the tracker is enabled with Accessibility (the setup card's rule).
    @ObservationIgnored var trackerSetUp: () async -> Bool = { false }
    /// The Macs' `LiveState` activity (iPad footer).
    @ObservationIgnored var remoteActivity: () async -> LiveState.MacActivity? = { nil }
    /// The app name of a bundle identifier (Mac: installed apps).
    @ObservationIgnored var appName: (String) -> String? = { _ in nil }
    @ObservationIgnored var isRecordingMac = true
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
    /// The focused heatmap cell (row id, hour) for the arrow keys.
    var focusedCell: (row: Int, hour: Int)?

    private(set) var summary: ActivitySummary?
    private(set) var health: ActivityHealth?
    private(set) var emptyState: ActivityEmptyState = .panels
    private(set) var contextColors: [String: Int] = [:]
    private(set) var isLoading = false
    /// The range revision the figures belong to; arrows keep the filter.
    @ObservationIgnored private var seenRevision = -1
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
    /// thread, keeping the previous figures until it is ready.
    func reload() async {
        if range.revision != seenRevision, range.revision != arrowRevision, seenRevision >= 0 {
            contexts = []
            drill = nil
        }
        seenRevision = range.revision
        isLoading = true
        defer { isLoading = false }
        do {
            let days = days
            let interval = range.calendar.interval(of: days)
            let blocks = try await activity.blocks(in: interval, devices: nil)
            let details = isRecordingMac ? try await activity.details(for: blocks.map(\.id)) : [:]
            let input = ActivitySummaryInput(
                blocks: blocks,
                days: days,
                today: range.today,
                contexts: contexts,
                device: selectedDevice,
                details: details,
                exclusions: activity.exclusions
            )
            let summary = await Task.detached { ActivitySummary(input) }.value
            self.summary = summary
            if summary.hasBlocks {
                device[.activitySawBlock] = true
            }
            await loadHealth()
            emptyState = await ActivityEmptyState.resolve(
                summary: summary,
                everSawBlock: device[.activitySawBlock],
                trackerSetUp: trackerSetUp(),
                footerRed: health?.isRed ?? false
            )
            await assignColors(summary.ranking.map(\.context))
        } catch {
            Logging.logger(category: "Planner").error("Activity: \(String(describing: error), privacy: .public)")
        }
    }

    /// The footer, every 10 seconds while visible.
    func loadHealth() async {
        if isRecordingMac {
            health = await ActivityHealth(registration: registration(), state: activity.currentState(), now: clock.now)
        } else if let remote = await remoteActivity() {
            health = ActivityHealth(remote: remote, now: clock.now)
        } else {
            health = nil
        }
    }

    private func assignColors(_ contexts: [String]) async {
        guard let current = try? await store.value(.activityContextColors) else {
            return
        }
        let assigned = ContextPalette.assigning(contexts, to: current)
        if assigned != current {
            try? await store.set(.activityContextColors, assigned)
        }
        contextColors = assigned
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

    /// The Planner window reopened: the filter resets.
    func plannerReopened() {
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

    /// "Exclude <name> from tracking…" for a context (apps and sessions).
    func exclude(context: String) {
        guard let draft = TrackerExclusionDraft.forContext(context, bundleIdentifier: activity.bundleIdentifier(forContext: context)) else {
            return
        }
        router?.showTrackerSettings(exclusion: draft)
    }

    /// "Exclude <site> from tracking…" for a site row.
    func exclude(site: String) {
        router?.showTrackerSettings(exclusion: .forSite(site))
    }
}
