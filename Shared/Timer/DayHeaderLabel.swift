// DayHeaderLabel: a Timer list day's header on the Mac and iOS
// (timer.md §3; ios.md §2.6).

import SwiftUI
import TimeTrackingCore

/// The day's title, then its total, which counts up while an entry runs.
/// Font and padding stay with the list that shows it.
struct DayHeaderLabel: View {
    var day: TimerListDay
    var title: String
    var clock: any Clock

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(DurationText.clock(day.totalSeconds(at: clock.now)))
                    .monospacedDigit()
                    .accessibilityIdentifier("timer.dayTotal.\(day.day)")
            }
        }
        .accessibilityIdentifier("timer.day.\(day.day)")
    }
}
