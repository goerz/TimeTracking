// CalendarModel: the Calendar section's view state, loading, and navigation
// (spec_planner_calendar.md §1, §7). Geometry, overlaps, suggestions, and
// Fill Day come from the library; this model holds selection, drafts, and
// presentation state.

import Foundation
import Observation
import os
import TimeTrackingCore

/// Something selectable in the Calendar.
enum CalendarItemID: Hashable {
    case entry(EntryID)
    case block(ActivityBlock.ID)
    case timeBlock(CalendarEvent.ID)
    case event(CalendarEvent.ID)
}

/// Where a provisional entry came from.
enum CalendarDraftSource: Equatable {
    case drawn
    case block(ActivityBlock)
    case timeBlock(TimeBlock)
    case event(CalendarEvent)
}

/// A provisional entry with a dashed border and the edit popover open.
struct CalendarDraft: Equatable {
    var day: TrackingDay
    var interval: DateInterval
    var projectID: ProjectID?
    var task: String
    /// The engine's candidates (the popover lists the others under the task field).
    var candidates: [SuggestionCandidate] = []
    /// The query that produced them; `nil` when the engine supplied nothing.
    var query: SuggestionQuery?
    var source: CalendarDraftSource

    /// The engine's top candidate, when it supplied the suggestion.
    var suggested: SuggestionCandidate? {
        query == nil ? nil : candidates.first
    }
}

/// A pending overlap question (§2.6).
struct PendingOverlap: Equatable {
    enum Action: Equatable {
        case create(CalendarDraft)
        case change(EntryID)
        case duplicate(TimeEntry)
    }

    var prompt: OverlapPrompt
    var action: Action
}

/// The Calendar section.
@Observable
final class CalendarModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let device: DeviceSettings
    @ObservationIgnored let activity: any ActivityReading
    @ObservationIgnored let events: any CalendarEventStore
    @ObservationIgnored let engine: SuggestionEngine
    @ObservationIgnored weak var router: PlannerRouter?
    @ObservationIgnored weak var undoManager: UndoManager?
    /// `delete-block` to the tracker agent; `nil` where the log cannot be changed (iPad).
    @ObservationIgnored var sendTrackerCommand: ((String) async -> String?)?
    /// The URL scheme of project links in time blocks.
    @ObservationIgnored var urlScheme = "timetracking"
    /// Opens an event in Calendar.app (Mac).
    @ObservationIgnored var openEvent: (CalendarEvent) -> Void = { _ in }
    /// Called after entry writes (the Timer re-reads).
    @ObservationIgnored var entriesChanged: () async -> Void = {}
    /// Whether this device shows the open block, gap labels, and Delete This Activity.
    @ObservationIgnored var isRecordingMac = true

    var calendar = TrackingCalendar(timeZone: .current)
    var firstDay: TrackingDay
    var visibleDays: Int {
        didSet { device[.calendarVisibleDays] = visibleDays }
    }

    var pointsPerHour: Double {
        didSet { device[.calendarPointsPerHour] = pointsPerHour }
    }

    var showsActivity: Bool {
        didSet { device[.calendarShowsActivity] = showsActivity }
    }

    var showsCalendar: Bool {
        didSet { device[.calendarShowsCalendar] = showsCalendar }
    }

    var shownCalendars: [CalendarChoice] {
        didSet { device[.calendarShownCalendars] = shownCalendars }
    }

    // Loaded data.
    private(set) var entries: [EntryListing] = []
    private(set) var blocks: [ActivityBlock] = []
    private(set) var timeBlocks: [TimeBlock] = []
    private(set) var externalEvents: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var projects: [Project] = []
    /// Each project with its area and client, for chips and labels.
    private(set) var projectRows: [ProjectID: ProjectRow] = [:]
    private(set) var summary: CalendarSummary?
    private(set) var timeBlockState: TimeBlockCalendarState?
    /// Gap causes per day ("idle 22m"), Mac only.
    private(set) var gapLabels: [TrackingDay: [(Date, String)]] = [:]

    // Synced settings.
    private(set) var snapMinutes = 5
    private(set) var fillMinMinutes = 5
    private(set) var trainDays = 180
    var rules: [SuggestionRule] = []

    /// Presentation state.
    var selection: Set<CalendarItemID> = []
    /// The stored entry whose edit popover is open.
    var editingEntry: EntryID?
    var draft: CalendarDraft?
    var blockDraft: TimeBlockDraft?
    var pendingOverlap: PendingOverlap?
    /// "Entries can't be in the future" (3 s) or "Deleted … Undo" (8 s).
    var notice: CalendarNotice?
    /// "Discard the running entry?"
    var confirmsRunningDelete = false
    /// "Delete this activity?"
    var blockToDelete: ActivityBlock?
    var trackerError: String?
    var fillDay: FillDayModel?
    var showsOptions = false
    var showsSuggestions = false
    var showsMonthPicker = false
    /// Pulsed cards after `showCalendar` (until `pulseEnds`).
    var highlight: (day: TrackingDay, highlight: BlockHighlight)?
    var pulseEnds: Date?
    /// The hour the view scrolls to the top, bumped per request.
    var scrollRequest: (hour: Double, serial: Int)?
    private(set) var lastError: String?

    @ObservationIgnored var pendingUndo: Task<Void, Never>?
    /// The suggestions index was loaded (from the cache or rebuilt) once.
    @ObservationIgnored var engineLoaded = false

    init(
        store: TimeStore,
        clock: any Clock,
        device: DeviceSettings,
        activity: any ActivityReading,
        events: any CalendarEventStore,
        engine: SuggestionEngine
    ) {
        self.store = store
        self.clock = clock
        self.device = device
        self.activity = activity
        self.events = events
        self.engine = engine
        let visible = min(7, max(1, device[.calendarVisibleDays]))
        self.visibleDays = visible
        self.pointsPerHour = CalendarZoom.clamped(device[.calendarPointsPerHour])
        self.showsActivity = device[.calendarShowsActivity]
        self.showsCalendar = device[.calendarShowsCalendar]
        self.shownCalendars = device[.calendarShownCalendars]
        let today = TrackingCalendar(timeZone: .current).day(containing: clock.now)
        self.firstDay = CalendarStrip.firstDay(centering: today, visibleDays: visible)
    }

    // MARK: Days

    var today: TrackingDay {
        calendar.day(containing: clock.now)
    }

    var days: [TrackingDay] {
        (0 ..< visibleDays).map { firstDay.adding(days: $0) }
    }

    var visibleInterval: DateInterval {
        calendar.interval(of: firstDay ... firstDay.adding(days: visibleDays - 1))
    }

    /// "Mon, Oct 26 – Fri, Oct 30 · W44".
    var rangeLabel: String {
        CalendarStrip.label(first: firstDay, count: visibleDays)
    }

    /// The visible columns of each day.
    var columns: [CalendarColumn] {
        CalendarColumn.allCases.filter { column in
            switch column {
            case .activity: showsActivity
            case .tracked: true
            case .calendar: showsCalendar
            }
        }
    }

    func axis(_ day: TrackingDay) -> CalendarDayAxis {
        CalendarDayAxis(day: day, calendar: calendar, pointsPerHour: pointsPerHour)
    }

    func editing(_ day: TrackingDay, option: Bool = false, limitToNow: Bool = true) -> CalendarEditing {
        CalendarEditing(
            day: calendar.interval(of: day),
            now: clock.now,
            snap: CalendarSnap(minutes: option ? 1 : snapMinutes),
            limitToNow: limitToNow
        )
    }

    // MARK: Loading

    /// Re-reads entries, blocks, events, settings, and the summary.
    func reload() async {
        do {
            snapMinutes = try await store.value(.calendarSnapMinutes)
            fillMinMinutes = try await store.value(.fillMinMinutes)
            trainDays = try await store.value(.trainDays)
            rules = try await store.value(.suggestionRules)
            let interval = visibleInterval
            let found = try await store.entries(in: interval, includeDeleted: false)
            entries = try await store.listings(for: found)
            let rows = try await store.projects(filter: ProjectFilter(state: .all))
            projects = rows.map(\.project)
            projectRows = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let loaded = try await activity.blocks(in: interval, devices: nil)
            blocks = isRecordingMac ? loaded : loaded.filter { !$0.isOpen }
            await loadEvents(around: interval)
            if !engineLoaded {
                engineLoaded = true
                await engine.load(titles: trainingTitles())
            }
            summary = CalendarSummary(
                days: days,
                calendar: calendar,
                entries: entries,
                activity: blocks,
                timeBlocks: timeBlocks.map(\.event.interval),
                now: clock.now
            )
            if isRecordingMac {
                await loadGapLabels()
            }
            await assignContextColors()
        } catch {
            report(error)
        }
    }

    /// The time-block calendar and the checked calendars over the visible
    /// range plus one day on each side.
    func loadEvents(around interval: DateInterval) async {
        guard showsCalendar else {
            return
        }
        if events.access() == .notDetermined {
            _ = await events.requestAccess()
        }
        let setting = await (try? store.value(.timeBlockCalendarID))
        let deviceID = device[.calendarTimeBlockCalendar]
        let resolution = TimeBlockCalendar.resolve(store: events, settingID: setting, deviceID: deviceID.isEmpty ? nil : deviceID)
        timeBlockState = resolution.state
        if let id = resolution.resolvedID {
            device[.calendarTimeBlockCalendar] = id
        }
        if let id = resolution.settingToWrite {
            try? await store.set(.timeBlockCalendarID, id)
        }
        guard events.access() == .fullAccess else {
            timeBlocks = []
            externalEvents = []
            return
        }
        calendars = events.calendars()
        let wide = DateInterval(start: interval.start - 86_400, end: interval.end + 86_400)
        if case let .ready(blockCalendar) = resolution.state {
            let found = (try? events.events(in: wide, calendarIDs: [blockCalendar.id])) ?? []
            timeBlocks = found.map { TimeBlock(event: $0, projects: projects) }
        } else {
            timeBlocks = []
        }
        let blockCalendarID = timeBlockCalendar?.id
        let shown = Set(calendars.filter { shownCalendars.contains($0.choice) && $0.id != blockCalendarID }.map(\.id))
        externalEvents = (try? events.events(in: wide, calendarIDs: shown)) ?? []
    }

    var timeBlockCalendar: CalendarInfo? {
        if case let .ready(calendar) = timeBlockState {
            return calendar
        }
        return nil
    }

    /// The color of an external event's calendar.
    func color(of event: CalendarEvent) -> String {
        calendars.first { $0.id == event.calendarID }?.color ?? "#8E8E93"
    }

    /// Context colors for contexts seen for the first time (§1.3 of the Activity spec).
    func assignContextColors() async {
        if let assigned = try? await store.assignContextColors(blocks.flatMap(\.contexts)) {
            contextColors = assigned
        }
    }

    private(set) var contextColors: [String: Int] = [:]

    private func loadGapLabels() async {
        var labels: [TrackingDay: [(Date, String)]] = [:]
        let byDevice = Dictionary(grouping: blocks.filter { !$0.isOpen }) { "\($0.device) \($0.localDay)" }
        for group in byDevice.values {
            let sorted = group.sorted { $0.start < $1.start }
            for (previous, next) in zip(sorted, sorted.dropFirst()) where next.start.timeIntervalSince(previous.end) > 900 {
                let details = await (try? activity.details(for: [previous.id, next.id])) ?? [:]
                guard !details.isEmpty else {
                    continue
                }
                let gap = DateInterval(start: previous.end, end: next.start)
                let cause = ActivitySummary.cause(of: gap, details: Array(details.values), idleClose: 300)
                guard cause != .unknown, let day = TrackingDay(previous.localDay) else {
                    continue
                }
                labels[day, default: []].append((gap.start, "\(cause.title) \(ActivityText.duration(Int(gap.duration)))"))
            }
        }
        gapLabels = labels
    }

    // MARK: Helpers

    func report(_ error: any Error) {
        lastError = UserMessage.text(for: error)
        Logging.logger(category: "Planner").error("Calendar: \(String(describing: error), privacy: .public)")
    }

    func listing(_ id: EntryID) -> EntryListing? {
        entries.first { $0.entry.id == id }
    }

    func project(_ id: ProjectID?) -> Project? {
        id.flatMap { id in projects.first { $0.id == id } }
    }

    /// The chip label of a project: name, client, area, color.
    func label(_ id: ProjectID?) -> ProjectLabel {
        id.flatMap { projectRows[$0] }.map(ProjectLabel.init) ?? .noProject
    }

    /// Waits for a pending undo (tests).
    func waitForUndo() async {
        await pendingUndo?.value
    }
}

/// A transient notice of the Calendar.
struct CalendarNotice: Equatable {
    var text: String
    /// Seconds it stays.
    var duration: TimeInterval
    /// Deleted entries the notice's Undo restores.
    var deleted: [EntryID] = []
}
