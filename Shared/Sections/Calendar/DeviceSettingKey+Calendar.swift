// The Calendar's and Activity's per-device view state
// (calendar.md §6, activity.md §1.9).

import Foundation
import TimeTrackingCore

extension DeviceSettingKey where Value == Double {
    static var calendarPointsPerHour: Self {
        Self("planner.calendar.pointsPerHour", default: CalendarZoom.defaultPointsPerHour)
    }

    /// The day width, the horizontal zoom.
    static var calendarDayWidth: Self {
        Self("planner.calendar.dayWidth", default: CalendarViewport.defaultDayWidth)
    }
}

extension DeviceSettingKey where Value == Bool {
    static var calendarShowsActivity: Self {
        Self("planner.calendar.showsActivity", default: true)
    }

    static var calendarShowsCalendar: Self {
        Self("planner.calendar.showsCalendar", default: true)
    }

    /// A block existed once; the Activity setup card never returns.
    static var activitySawBlock: Self {
        Self("planner.activity.sawBlock", default: false)
    }
}

extension DeviceSettingKey where Value == ReportFilters {
    /// The Calendar's Filters (§1.6).
    static var calendarFilters: Self {
        Self("planner.calendar.filters", default: ReportFilters())
    }
}

extension DeviceSettingKey where Value == String {
    /// The resolved time-block calendar identifier (device state).
    static var calendarTimeBlockCalendar: Self {
        Self("planner.calendar.timeBlockCalendar", default: "")
    }
}
