// RunningDurationText: the running row's live duration on the Mac and iOS
// (spec_timer_window.md §3; spec_ios.md §2.6; spec_design.md §7.1).

import SwiftUI
import TimeTrackingCore

/// The running entry's `h:mm:ss` in the accent color; only the text ticks.
struct RunningDurationText: View {
    var entry: TimeEntry
    var clock: any Clock

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(DurationText.clock(entry.seconds(at: clock.now)))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
        }
    }
}
