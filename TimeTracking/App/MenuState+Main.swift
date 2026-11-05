// MenuState+Main: the menu context of the main window and the Mini Timer
// (timer.md §9).

import SwiftUI
import TimeTrackingCore

extension MenuState {
    /// `mainKey`: the main window is key; `timerViewKey`: a Timer view is in
    /// the key window (the Mini Timer, or the main window's Timer tab). The
    /// Timer counts as "Timer key" in either window, a section as "section
    /// key".
    init(app: AppModel?, mainKey: Bool, timerViewKey: Bool) {
        let showsTimer = app?.showsTimer ?? true
        self.init(
            router: app?.sections,
            timerKey: mainKey ? showsTimer : timerViewKey,
            sectionKey: mainKey && !showsTimer
        )
    }
}
