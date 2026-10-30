// The Planner's per-device view state (spec_planner_projects.md §1.1,
// spec_planner_reports.md §9).

import Foundation
import TimeTrackingCore

extension DeviceSettingKey where Value == PlannerSection {
    static var plannerSection: Self {
        Self("planner.section", default: .projects)
    }
}

extension DeviceSettingKey where Value == Bool {
    static var plannerSidebarVisible: Self {
        Self("planner.sidebarVisible", default: true)
    }
}

extension DeviceSettingKey where Value == ReportRange {
    /// The range shared by Reports and Activity.
    static var plannerRange: Self {
        Self("planner.range", default: .standard)
    }
}

extension DeviceSettingKey where Value == ProjectTableOptions {
    static var projectsOptions: Self {
        Self("planner.projects.options", default: ProjectTableOptions())
    }
}

extension DeviceSettingKey where Value == [String: Set<String>] {
    /// Collapsed group ids per grouping.
    static var projectsCollapsed: Self {
        Self("planner.projects.collapsed", default: [:])
    }
}

extension DeviceSettingKey where Value == Data {
    /// The table's encoded column customization (visibility and widths).
    static var projectsColumns: Self {
        Self("planner.projects.columns", default: Data())
    }
}

extension DeviceSettingKey where Value == ReportViewState {
    static var reportsState: Self {
        Self("planner.reports.state", default: ReportViewState())
    }
}
