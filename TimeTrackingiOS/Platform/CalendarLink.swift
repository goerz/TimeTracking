// CalendarLink: "Open in Calendar" on the iPad, through the Calendar app's
// `calshow:` URL, which SwiftUI does not provide (spec_planner_calendar.md §4.3).

import UIKit

/// Opens the Calendar app.
enum CalendarLink {
    /// The Calendar app at `date`.
    static func open(_ date: Date) {
        if let url = URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)") {
            UIApplication.shared.open(url)
        }
    }
}
