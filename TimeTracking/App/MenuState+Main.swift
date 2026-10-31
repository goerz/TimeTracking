// MenuState+Main: the menu context of the main window and the Mini Timer
// (experiment).

import SwiftUI
import TimeTrackingCore

extension MenuState {
    /// `mainKey`: the main window is key; `timerViewKey`: a Timer view is in
    /// the key window (the Mini Timer, or the main window's Timer tab). The
    /// Timer counts as "Timer key" in either window, a Planner tab as
    /// "Planner key".
    init(app: AppModel?, mainKey: Bool, timerViewKey: Bool) {
        let showsTimer = app?.showsTimer ?? true
        self.init(
            router: app?.planner,
            timerKey: mainKey ? showsTimer : timerViewKey,
            plannerKey: mainKey && !showsTimer
        )
    }
}
