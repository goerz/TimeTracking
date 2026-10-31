// PlannerRouter: the Planner's sections, the requests that switch between
// them, and their links to the Timer (spec_planner_projects.md §1.3). On the
// Mac the router opens the Planner window; on the iPad it selects tabs.

import Foundation
import Observation
import TimeTrackingCore

/// The four sections, in sidebar (and tab) order.
nonisolated enum PlannerSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case projects
    case calendar
    case reports
    case activity

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .calendar: "Calendar"
        case .reports: "Reports"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .projects: SymbolName.projects
        case .calendar: SymbolName.calendar
        case .reports: SymbolName.reports
        case .activity: SymbolName.activity
        }
    }

    /// ⌘1 to ⌘4.
    var key: Character {
        switch self {
        case .projects: "1"
        case .calendar: "2"
        case .reports: "3"
        case .activity: "4"
        }
    }
}

/// What the Calendar pulses after `showCalendar` (spec_planner_calendar.md §1.2).
nonisolated enum BlockHighlight: Hashable, Sendable {
    /// One hour of the day.
    case hour(Int)
    /// One context on the day.
    case context(String)
}

/// A pending `showCalendar` request; the Calendar section consumes it.
nonisolated struct CalendarRequest: Equatable, Sendable {
    var day: TrackingDay
    var hour: Int?
    var highlight: BlockHighlight?
}

/// Selects sections and hands them requests; no section changes another's
/// state directly.
@Observable
final class PlannerRouter {
    @ObservationIgnored let device: DeviceSettings

    var section: PlannerSection {
        didSet {
            device[.plannerSection] = section
            sectionChanged(section)
        }
    }

    /// The range shared by Reports and Activity.
    let range: DateRangeModel
    let projects: ProjectsModel
    let reports: ReportsModel
    let calendar: CalendarModel
    let activity: ActivityModel
    /// The latest `showCalendar` request; the Calendar section consumes it.
    var calendarRequest: CalendarRequest?
    /// Bumped by `showActivity`, for the Activity section.
    private(set) var activityRequests = 0

    /// Opens the Planner window (Mac) or does nothing (iPad tabs).
    @ObservationIgnored var openWindow: () -> Void = {}
    /// After every section change (the iPad selects the matching tab).
    @ObservationIgnored var sectionChanged: (PlannerSection) -> Void = { _ in }
    /// Opens Settings on the Tracker pane with an exclusion prefilled.
    @ObservationIgnored var openTrackerSettings: (TrackerExclusionDraft?) -> Void = { _ in }
    /// Puts text on the pasteboard (⌘C in the tables).
    @ObservationIgnored var copyText: (String) -> Void = { _ in }

    /// `activity` reads the block log; `events` is EventKit (Mac, iPad) or
    /// an in-memory store; `suggestionsCache` spares the launch rebuild.
    init(
        store: TimeStore,
        clock: any Clock,
        device: DeviceSettings,
        activity: any ActivityReading = InMemoryActivityStore(),
        events: any CalendarEventStore = InMemoryCalendarEventStore(access: .denied),
        suggestionsCache: URL? = nil
    ) {
        self.device = device
        self.section = device[.plannerSection]
        let range = DateRangeModel(clock: clock, device: device)
        self.range = range
        self.projects = ProjectsModel(store: store, clock: clock, device: device)
        self.reports = ReportsModel(store: store, clock: clock, device: device, range: range)
        let engine = SuggestionEngine(store: store, activity: activity, cacheURL: suggestionsCache)
        self.calendar = CalendarModel(store: store, clock: clock, device: device, activity: activity, events: events, engine: engine)
        self.activity = ActivityModel(store: store, clock: clock, device: device, activity: activity, range: range)
        projects.router = self
        reports.router = self
        calendar.router = self
        self.activity.router = self
    }

    /// The sections' links to the Timer: Start Timer and Continue act
    /// through it, and every other write of a section ends in `afterWrite`.
    func wireTimer(_ timer: TimerModel, afterWrite: @escaping () async -> Void) {
        projects.startTimer = { [weak timer] id in await timer?.startEmpty(on: id) }
        reports.continueEntry = { [weak timer] id in await timer?.continueEntry(id) }
        reports.entriesChanged = afterWrite
        calendar.entriesChanged = afterWrite
    }

    /// Applies a pending `showCalendar` request to the Calendar section.
    func consumeCalendarRequest() async {
        guard let request = calendarRequest else {
            return
        }
        calendarRequest = nil
        await calendar.apply(request)
    }

    /// ⌘1 to ⌘4 and the sidebar.
    func select(_ section: PlannerSection) {
        self.section = section
    }

    /// Selects Projects with its current view state.
    func showProjects() {
        openWindow()
        section = .projects
        projects.showTable()
    }

    /// Selects Projects and reveals the project's row (`timetracking://project/<uuid>`).
    func showProject(_ id: ProjectID) async {
        openWindow()
        section = .projects
        await projects.reveal(id)
    }

    /// Selects Projects and shows Clients & Areas, with `client` selected.
    func showClientsAndAreas(client: ClientID? = nil) {
        openWindow()
        section = .projects
        projects.showClientsAndAreas(client: client)
    }

    /// Selects Calendar and leaves the request for it.
    func showCalendar(day: TrackingDay, hour: Int? = nil, highlight: BlockHighlight? = nil) {
        openWindow()
        section = .calendar
        calendarRequest = CalendarRequest(day: day, hour: hour, highlight: highlight)
    }

    /// Selects Reports with the range and only the given filters.
    func showReports(range: ReportRange? = nil, filter: ReportFilters = ReportFilters()) async {
        openWindow()
        section = .reports
        await reports.show(range: range, filters: filter)
    }

    /// Selects Activity with the shared range (changed when given).
    func showActivity(range: ReportRange? = nil) {
        openWindow()
        if let range {
            self.range.set(range)
        }
        section = .activity
        activityRequests += 1
    }

    /// Opens Settings on the Tracker pane, with an unsaved exclusion draft.
    func showTrackerSettings(exclusion: TrackerExclusionDraft? = nil) {
        openTrackerSettings(exclusion)
    }
}
