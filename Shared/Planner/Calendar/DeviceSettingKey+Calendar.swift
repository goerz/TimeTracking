// The Calendar's and Activity's per-device view state
// (spec_planner_calendar.md §7, spec_planner_activity.md §1.9).

import Foundation
import TimeTrackingCore

extension DeviceSettingKey where Value == Double {
    static var calendarPointsPerHour: Self {
        Self("planner.calendar.pointsPerHour", default: CalendarZoom.defaultPointsPerHour)
    }
}

extension DeviceSettingKey where Value == Int {
    static var calendarVisibleDays: Self {
        Self("planner.calendar.visibleDays", default: CalendarStrip.defaultVisibleDays)
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

extension DeviceSettingKey where Value == [CalendarChoice] {
    /// External calendars to show, as (account, calendar) titles.
    static var calendarShownCalendars: Self {
        Self("planner.calendar.shownCalendars", default: [])
    }
}

extension DeviceSettingKey where Value == String {
    /// The resolved time-block calendar identifier (device state).
    static var calendarTimeBlockCalendar: Self {
        Self("planner.calendar.timeBlockCalendar", default: "")
    }
}
