// CalendarModel: the Calendar section's view state, loading, and navigation
// (calendar.md §1, §6). Geometry and overlaps come from the library;
// this model holds selection, drafts, and presentation state.

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

/// A provisional entry with a dashed border and the edit popover open.
struct CalendarDraft: Equatable {
    var day: TrackingDay
    var interval: DateInterval
    var projectID: ProjectID?
    var task: String
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

/// A card's move or resize while the pointer holds it (§2.4).
struct CalendarCardDrag: Equatable {
    var item: CalendarItemID
    /// The column the drag started in.
    var day: TrackingDay
    /// Where it started in the card: a new start is a new drag.
    var start: CGPoint
    /// Escape cancelled it; the rest of the gesture does nothing.
    var cancelled = false
}

/// The Calendar section.
@Observable
final class CalendarModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let device: DeviceSettings
    @ObservationIgnored let activity: any ActivityReading
    @ObservationIgnored let events: any CalendarEventStore
    @ObservationIgnored weak var router: SectionRouter?
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
    @ObservationIgnored var isMac = true

    /// The days the columns show (the synced start of day, read on every reload).
    var calendar: TrackingCalendar

    /// The strip of days (§1.2). Every sideways scroll changes it, so only
    /// the strip itself reads it; other views read the values derived below,
    /// which change only when they differ.
    var viewport: CalendarViewport {
        didSet { viewportChanged() }
    }

    /// Derived from the viewport; only `viewportChanged()` sets them.
    /// The day width, the horizontal zoom (per device).
    var dayWidth: Double
    /// The days with a part in the viewport, left to right.
    var days: [TrackingDay]
    /// The days at least half visible: the subtitle, the date menu, and the
    /// summary strip.
    var shownDays: [TrackingDay]
    /// Until the first width arrives, the viewport waits to center today.
    @ObservationIgnored var centersTodayOnLayout = true
    /// The days the loaded data covers.
    @ObservationIgnored var loadedDays: ClosedRange<TrackingDay>?
    @ObservationIgnored var loadTask: Task<Void, Never>?
    /// Counts reloads; only the latest one assigns what it read.
    @ObservationIgnored var loadGeneration = 0
    /// Set when the arrows or a header click snap the days, until the next
    /// trackpad gesture.
    @ObservationIgnored var ignoresMomentum = false

    var pointsPerHour: Double {
        didSet { device[.calendarPointsPerHour] = pointsPerHour }
    }

    var showsActivity: Bool {
        didSet { device[.calendarShowsActivity] = showsActivity }
    }

    var showsCalendar: Bool {
        didSet { device[.calendarShowsCalendar] = showsCalendar }
    }

    // Loaded data.
    private(set) var entries: [EntryListing] = []
    private(set) var blocks: [ActivityBlock] = []
    /// The tracker's background blocks: work while the user was away (§3.1).
    private(set) var backgroundBlocks: [ActivityBlock] = []
    private(set) var timeBlocks: [TimeBlock] = []
    private(set) var externalEvents: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var projects: [Project] = []
    /// Each project with its area and client, for chips and labels.
    private(set) var projectRows: [ProjectID: ProjectRow] = [:]
    /// The Filters tree's clients, areas, and projects (retired included).
    private(set) var filterTree = CalendarFilterTree()

    /// The Filters (per device) and the toolbar's search (not stored), as
    /// in Reports; entries they leave out are faded (§1.6).
    var filters: ReportFilters {
        didSet {
            device[.calendarFilters] = filters
            refreshTotals()
        }
    }

    var search = "" {
        didSet {
            if search != oldValue {
                refreshTotals()
            }
        }
    }

    var showsFilters = false
    /// Whether the search field has the focus (the plain keys are off).
    var searchFocused = false
    /// Bumped to focus the search field (⌘F).
    var searchFocusRequests = 0
    /// The summary strip's figures over the shown days (`refreshSummary()`).
    var summary: CalendarSummary?
    /// Each loaded day's column totals (the day headers).
    var dayTotals: [TrackingDay: CalendarSummary.DayTotals] = [:]
    private(set) var timeBlockState: TimeBlockCalendarState?
    /// Sleep and workouts from Apple Health in the visible range, of the
    /// kinds the settings show.
    private(set) var healthPeriods: [HealthPeriod] = []
    /// Gaps per day with their duration ("22m"), Mac only.
    private(set) var gapLabels: [TrackingDay: [(DateInterval, String)]] = [:]

    // Synced settings, written through the settings methods (§6).
    var snapMinutes = 5
    var shownCalendars: [CalendarChoice] = []
    var showSleep = false
    var showWorkouts = false
    /// The areas whose reports count sleep and workouts (§6).
    var healthAreas: [HealthPeriod.Kind: AreaID] = [:]
    /// The settings' area menus: every live area, "Client" or "Client · Area".
    var healthAreaChoices: [(id: AreaID, title: String)] = []
    /// The settings' line on the iPhone's last import; nil while both are off.
    var healthImport: HealthImportStatus.Summary?

    /// Presentation state.
    var selection: Set<CalendarItemID> = []
    /// The stored entry whose edit popover is open.
    var editingEntry: EntryID?
    var draft: CalendarDraft?
    var blockDraft: TimeBlockDraft?
    var pendingOverlap: PendingOverlap?
    var cardDrag: CalendarCardDrag?
    /// The part of the columns in view, from their top; a drag dropped
    /// above or below it is outside them.
    @ObservationIgnored var visibleColumnsY: ClosedRange<Double>?
    /// "Entries can't be in the future" (3 s) or "Deleted … Undo" (8 s).
    var notice: CalendarNotice?
    /// "Discard the running entry?"
    var confirmsRunningDelete = false
    /// "Delete this activity?"
    var blockToDelete: ActivityBlock?
    var trackerError: String?
    var showsMonthPicker = false
    /// Pulsed cards after `showCalendar` (until `pulseEnds`).
    var highlight: (day: TrackingDay, highlight: BlockHighlight)?
    var pulseEnds: Date?
    /// The hour the view scrolls to the top, bumped per request.
    var scrollRequest: (hour: Double, serial: Int)?
    private(set) var lastError: String?

    @ObservationIgnored var pendingUndo: Task<Void, Never>?

    init(
        store: TimeStore,
        clock: any Clock,
        device: DeviceSettings,
        activity: any ActivityReading,
        events: any CalendarEventStore
    ) {
        self.store = store
        self.clock = clock
        self.device = device
        self.activity = activity
        self.events = events
        self.pointsPerHour = CalendarZoom.clamped(device[.calendarPointsPerHour])
        self.showsActivity = device[.calendarShowsActivity]
        self.showsCalendar = device[.calendarShowsCalendar]
        self.filters = device[.calendarFilters]
        let calendar = store.displayCalendar()
        self.calendar = calendar
        let today = calendar.day(containing: clock.now)
        let viewport = CalendarViewport(firstDay: today, dayWidth: device[.calendarDayWidth])
        self.viewport = viewport
        self.dayWidth = viewport.dayWidth
        self.days = viewport.touchedDays
        self.shownDays = viewport.shownDays
    }

    // MARK: Loading

    /// Re-reads entries, blocks, events, settings, and the summary over the
    /// days in view and as many again on either side (at least two), so a
    /// sideways scroll finds them loaded. Everything is read first and
    /// assigned at once, and only when no later reload started meanwhile,
    /// so overlapping reloads (an edit starts two) never leave a mix of
    /// old and new data, and the loaded days are claimed only once their
    /// data is in.
    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            try await readSyncedSettings()
            let pad = max(2, days.count)
            let range = days[0].adding(days: -pad) ... days[days.count - 1].adding(days: pad)
            let interval = calendar.interval(of: range)
            let found = try await store.entries(in: interval, includeDeleted: false)
            let entries = try await store.listings(for: found)
            let rows = try await store.projects(filter: ProjectFilter(state: .all))
            let filterTree = try await CalendarFilterTree(
                clients: store.clients(includeRetired: true),
                areas: store.areas(of: nil, includeRetired: true),
                projects: rows
            )
            let loaded = try await activity.blocks(in: interval, devices: nil)
            let background = try await activity.backgroundBlocks(in: interval, devices: nil)
            let healthPeriods = try await loadHealthPeriods(in: interval)
            guard generation == loadGeneration else {
                return
            }
            self.entries = entries
            projects = rows.map(\.project)
            self.filterTree = filterTree
            projectRows = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            blocks = isMac ? loaded : loaded.filter { !$0.isOpen }
            backgroundBlocks = background
            self.healthPeriods = healthPeriods
            loadedDays = range
            refreshTotals()
            if isMac {
                loadGapLabels()
            }
            await loadEvents(around: interval, generation: generation)
        } catch {
            if generation == loadGeneration {
                report(error)
            }
        }
    }

    /// The Calendar settings (the settings window's Calendar pane, the
    /// iPad's Settings): the synced values, the calendars, and the
    /// time-block calendar, without asking for calendar access.
    func loadSettings() async {
        do {
            try await readSyncedSettings()
        } catch {
            report(error)
        }
        await resolveTimeBlockCalendar()
        calendars = events.access() == .fullAccess ? events.calendars() : []
        await loadHealthAreaChoices()
    }

    private func readSyncedSettings() async throws {
        calendar = store.displayCalendar(timeZone: calendar.timeZone)
        snapMinutes = try await store.value(.calendarSnapMinutes)
        shownCalendars = try await store.value(.calendarShownCalendars)
        showSleep = try await store.value(.calendarShowSleep)
        showWorkouts = try await store.value(.calendarShowWorkouts)
        healthAreas[.sleep] = try await store.value(.calendarSleepAreaID)
        healthAreas[.workout] = try await store.value(.calendarWorkoutAreaID)
        try await readHealthImport()
    }

    /// The time-block calendar and the checked calendars over the visible
    /// range plus one day on each side.
    /// With `generation`, nothing is assigned once a later reload started.
    func loadEvents(around interval: DateInterval, generation: Int? = nil) async {
        guard showsCalendar else {
            return
        }
        if events.access() == .notDetermined {
            _ = await events.requestAccess()
        }
        await resolveTimeBlockCalendar()
        guard generation == nil || generation == loadGeneration, showsCalendar else {
            return
        }
        guard events.access() == .fullAccess else {
            timeBlocks = []
            externalEvents = []
            return
        }
        calendars = events.calendars()
        let wide = DateInterval(start: interval.start - 86_400, end: interval.end + 86_400)
        if case let .ready(blockCalendar) = timeBlockState {
            let found = (try? events.events(in: wide, calendarIDs: [blockCalendar.id])) ?? []
            timeBlocks = found.map { TimeBlock(event: $0, projects: projects) }
        } else {
            timeBlocks = []
        }
        let blockCalendarID = timeBlockCalendar?.id
        let shown = Set(calendars.filter { shownCalendars.contains($0.choice) && $0.id != blockCalendarID }.map(\.id))
        externalEvents = (try? events.events(in: wide, calendarIDs: shown)) ?? []
    }

    /// Resolves the time-block calendar (§4.1): by identifier, else by
    /// title in the iCloud source, creating it only when both fail.
    func resolveTimeBlockCalendar() async {
        let setting = await (try? store.value(.timeBlockCalendarID))
        let title = await (try? store.value(.timeBlockCalendarTitle))
        let deviceID = device[.calendarTimeBlockCalendar]
        let resolution = TimeBlockCalendar.resolve(
            store: events,
            settingID: setting,
            settingTitle: title,
            deviceID: deviceID.isEmpty ? nil : deviceID
        )
        await apply(resolution)
    }

    /// Keeps a resolution's state and identifier and writes its settings.
    func apply(_ resolution: TimeBlockCalendar.Resolution) async {
        timeBlockState = resolution.state
        if let id = resolution.resolvedID {
            device[.calendarTimeBlockCalendar] = id
        }
        guard let id = resolution.settingToWrite else {
            return
        }
        do {
            try await store.set(.timeBlockCalendarID, id)
            try await store.set(.timeBlockCalendarTitle, resolution.titleToWrite)
        } catch {
            report(error)
        }
    }

    /// Gaps over 15 minutes between blocks of any device, labeled with
    /// their duration (§3.1).
    private func loadGapLabels() {
        var labels: [TrackingDay: [(DateInterval, String)]] = [:]
        let hour = calendar.startOfDayHour
        for (day, group) in Dictionary(grouping: blocks, by: { $0.shownDay(startOfDayHour: hour) }) {
            labels[day] = ActivityBlock.gaps(between: group, longerThan: 900).map { ($0, ActivityText.duration(Int($0.duration))) }
        }
        gapLabels = labels
    }

    // MARK: Helpers

    func report(_ error: any Error) {
        lastError = UserMessage.text(for: error)
        Logging.logger(category: "Sections").error("Calendar: \(String(describing: error), privacy: .public)")
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
