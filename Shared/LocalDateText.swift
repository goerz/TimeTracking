// LocalDateText: times and days in the system's format and zone, for the
// editors, the status item, and notifications (spec_timer_window.md §4;
// spec_menubar.md §2.1).

import Foundation

/// Dates as the system formats them for the user.
enum LocalDateText {
    /// The time of day in the system's 12- or 24-hour format.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Thu, Oct 29".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
