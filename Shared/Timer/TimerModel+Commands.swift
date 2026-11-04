// TimerModel+Commands: the timer label's text and the commands built from
// the others (spec_timer.md §2.1, §10; spec_ios.md §8).

import Foundation
import TimeTrackingCore

extension TimerModel {
    /// Seconds since the chain start, or 0 when idle.
    func elapsedSeconds(at now: Date) -> Int {
        guard let chainStart else {
            return 0
        }
        return max(0, Int(now.timeIntervalSince(chainStart).rounded(.down)))
    }

    /// The timer label without a Pomodoro: `h:mm:ss`, `0:00:00` when idle.
    func timerText(at now: Date) -> String {
        DurationText.clock(elapsedSeconds(at: now))
    }

    /// Stops the running entry only while it belongs to the chain of
    /// `root` (a notification's Stop for the entry it named).
    func stop(chainOf root: EntryID) async {
        await commitTask()
        do {
            let now = clock.now
            if try await store.transaction({ try $0.stop(chainOf: root, at: now) }) != nil {
                await clearDraft()
            }
            await refresh()
            await onChange?()
        } catch {
            report(error)
        }
    }

    /// The continue/stop shortcut: stop, or continue the most recent entry.
    func continueOrStop() async {
        if running != nil {
            await stop()
        } else {
            await continueEntry()
        }
    }
}
