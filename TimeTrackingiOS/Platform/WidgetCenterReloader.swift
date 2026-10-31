// WidgetCenterReloader: WidgetKit reloads of the widget timelines and the
// timer control (spec_ios.md §3.1, §5).

import Foundation
import TimeTrackingCore
import WidgetKit

/// Reloads every widget timeline and the timer control.
final class WidgetCenterReloader: WidgetReloading {
    func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reloadControls() {
        ControlCenter.shared.reloadControls(ofKind: WidgetKind.timerToggle)
    }
}
