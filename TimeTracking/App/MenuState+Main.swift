// MenuState+Main: the menu context of the one window (experiment).

import SwiftUI
import TimeTrackingCore

extension MenuState {
    /// The window is key: the Timer view counts as "Timer key", a Planner
    /// view as "Planner key".
    init(app: AppModel?, windowKey: Bool) {
        let showsTimer = app?.showsTimer ?? true
        self.init(router: app?.planner, timerKey: windowKey && showsTimer, plannerKey: windowKey && !showsTimer)
    }
}

extension PlannerSection {
    /// ⌘2 to ⌘5 in the one window's sidebar, after the Timer's ⌘1.
    var mainWindowKey: KeyEquivalent {
        KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 2)))
    }
}
