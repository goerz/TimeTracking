// SectionRouter: the main window's sections, the requests that switch
// between them, and their links to the Timer (spec_projects.md §1.3). On
// the Mac the router shows the main window; on the iPad it selects tabs.

import Foundation
import Observation
import TimeTrackingCore

/// The four sections, in sidebar (and tab) order after the Timer: the
/// daily ones first, then Projects, then the tracker's Activity.
nonisolated enum MainSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case calendar
    case reports
    case projects
    case activity

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .reports: "Reports"
        case .projects: "Projects"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: SymbolName.calendar
        case .reports: SymbolName.reports
        case .projects: SymbolName.projects
        case .activity: SymbolName.activity
        }
    }
}

/// What the Calendar pulses after `showCalendar` (spec_calendar.md §1.2).
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
final class SectionRouter {
    @ObservationIgnored let device: DeviceSettings

    var section: MainSection {
        didSet {
            device[.selectedSection] = section
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

    /// Shows the main window on the section just selected (Mac) or does
    /// nothing (iPad tabs, which follow `sectionChanged`).
    @ObservationIgnored var showMainWindow: (MainSection) -> Void = { _ in }
    /// After every section change (the iPad selects the matching tab).
    @ObservationIgnored var sectionChanged: (MainSection) -> Void = { _ in }
    /// Opens Settings on the Tracker pane with an exclusion prefilled.
    @ObservationIgnored var openTrackerSettings: (TrackerExclusionDraft?) -> Void = { _ in }
    /// Puts text on the pasteboard (⌘C in the tables).
    @ObservationIgnored var copyText: (String) -> Void = { _ in }

    /// `activity` reads the block log; `events` is EventKit (Mac, iPad) or
    /// an in-memory store.
    init(
        store: TimeStore,
        clock: any Clock,
        device: DeviceSettings,
        activity: any ActivityReading = InMemoryActivityStore(),
        events: any CalendarEventStore = InMemoryCalendarEventStore(access: .denied)
    ) {
        self.device = device
        self.section = device[.selectedSection]
        let range = DateRangeModel(clock: clock, device: device)
        self.range = range
        self.projects = ProjectsModel(store: store, clock: clock, device: device)
        self.reports = ReportsModel(store: store, clock: clock, device: device, range: range)
        self.calendar = CalendarModel(store: store, clock: clock, device: device, activity: activity, events: events)
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

    /// ⌘2 to ⌘5 and the sidebar.
    func select(_ section: MainSection) {
        self.section = section
    }

    /// Selects Projects with its current view state.
    func showProjects() {
        section = .projects
        showMainWindow(section)
    }

    /// Selects Projects and reveals the project's row (`timetracking://project/<uuid>`).
    func showProject(_ id: ProjectID) async {
        section = .projects
        showMainWindow(section)
        await projects.reveal(id)
    }

    /// Selects Calendar and leaves the request for it.
    func showCalendar(day: TrackingDay, hour: Int? = nil, highlight: BlockHighlight? = nil) {
        section = .calendar
        showMainWindow(section)
        calendarRequest = CalendarRequest(day: day, hour: hour, highlight: highlight)
    }

    /// Selects Reports with the range and only the given filters.
    func showReports(range: ReportRange? = nil, filter: ReportFilters = ReportFilters()) async {
        section = .reports
        showMainWindow(section)
        await reports.show(range: range, filters: filter)
    }

    /// Selects Activity with the shared range (changed when given).
    func showActivity(range: ReportRange? = nil) {
        if let range {
            self.range.set(range)
        }
        section = .activity
        showMainWindow(section)
        activityRequests += 1
    }

    /// Opens Settings on the Tracker pane, with an unsaved exclusion draft.
    func showTrackerSettings(exclusion: TrackerExclusionDraft? = nil) {
        openTrackerSettings(exclusion)
    }
}
