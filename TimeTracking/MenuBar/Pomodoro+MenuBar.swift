// Pomodoro+MenuBar: the Pomodoro countdown of the status item and its menu
// (menubar.md §1.1, §2.1).

import Foundation
import TimeTrackingCore

extension Pomodoro {
    /// The seconds since the phase ended, once it has (the over-states
    /// included), else `nil`.
    func overtime(at now: Date) -> Int? {
        guard let remaining = remaining(at: now), state.isPendingConfirmation || remaining < 0 else {
            return nil
        }
        return -min(remaining, 0)
    }

    /// The countdown in the menu bar: always `m:ss`, also for phases of an
    /// hour or more (unlike `countdownText`), and `+m:ss` once the phase has
    /// ended. Before the end it is padded to `phaseSeconds` as in
    /// `StatusItemPresenter.paddedCountdown`.
    func menuBarCountdown(at now: Date, paddedTo phaseSeconds: Int = 0) -> String? {
        if let over = overtime(at: now) {
            return "+" + DurationText.minutesSeconds(over)
        }
        return remaining(at: now).map { StatusItemPresenter.paddedCountdown($0, phaseSeconds: phaseSeconds) }
    }
}
