// The sections' per-device view state (the keys keep their former
// "planner." prefix, so stored state carries over) (projects.md §1.1,
// reports.md §9).

import Foundation
import TimeTrackingCore

extension DeviceSettingKey where Value == MainSection {
    static var selectedSection: Self {
        Self("planner.section", default: .projects)
    }
}

extension DeviceSettingKey where Value == ReportRange {
    /// The range shared by Reports and Activity.
    static var sharedRange: Self {
        Self("planner.range", default: .standard)
    }
}

extension DeviceSettingKey where Value == ReportRange {
    /// The Projects section's own range (default All time).
    static var projectsRange: Self {
        Self("planner.projects.range", default: .preset(.allTime))
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
