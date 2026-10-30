// PlannerRouter: the Planner's sections and the requests that switch
// between them (spec_planner_projects.md §1.3). On the Mac the router opens
// the Planner window; on the iPad it selects tabs.

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
        case .projects: "folder"
        case .calendar: "calendar"
        case .reports: "chart.bar"
        case .activity: "waveform.path.ecg"
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
        didSet { device[.plannerSection] = section }
    }

    /// The range shared by Reports and Activity.
    let range: DateRangeModel
    let projects: ProjectsModel
    let reports: ReportsModel
    /// The latest `showCalendar` request, for the Calendar section (step 7b).
    var calendarRequest: CalendarRequest?
    /// Bumped by `showActivity`, for the Activity section (step 7b).
    private(set) var activityRequests = 0

    /// Opens the Planner window (Mac) or does nothing (iPad tabs).
    @ObservationIgnored var openWindow: () -> Void = {}
    /// Opens Settings on the Tracker pane with an exclusion prefilled.
    @ObservationIgnored var openTrackerSettings: (String?) -> Void = { _ in }
    /// Puts text on the pasteboard (⌘C in the tables).
    @ObservationIgnored var copyText: (String) -> Void = { _ in }

    init(store: TimeStore, clock: any Clock, device: DeviceSettings) {
        self.device = device
        self.section = device[.plannerSection]
        let range = DateRangeModel(clock: clock, device: device)
        self.range = range
        self.projects = ProjectsModel(store: store, clock: clock, device: device)
        self.reports = ReportsModel(store: store, clock: clock, device: device, range: range)
        projects.router = self
        reports.router = self
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

    /// Opens Settings on the Tracker pane.
    func showTrackerSettings(exclusion: String? = nil) {
        openTrackerSettings(exclusion)
    }
}
