// AppModel+Changes: loading at launch, following the store's changes, and
// the start of a new shown day (timer.md §2; data_and_sync.md §7,
// §8; menubar.md §5).

import Foundation
import os
import TimeTrackingCore

extension AppModel {
    /// Loads everything; with `observing`, follows the store's changes.
    /// The stream is created before the first read, so a change committed
    /// while loading is not missed.
    func start(observing: Bool) async {
        let stream = observing ? store.changes : nil
        await pomodoro.loadSettings()
        await timer.refresh()
        lastRunningID = timer.running?.id
        await reloadLists()
        await tracker.refresh()
        guard let stream else {
            return
        }
        dayTask = Task { [weak self] in
            await self?.watchShownDay()
        }
        changeTask = Task { [weak self] in
            for await change in stream {
                guard let self else {
                    return
                }
                if Self.reloadsSections(change) {
                    // Another process's commit yields several such events at
                    // once: they share one reload, plus one more for those
                    // arriving while it runs.
                    reloadRequested = true
                    if reloadLoop == nil {
                        reloadLoop = Task { await self.runRequestedReloads() }
                    }
                } else {
                    await storeChanged(change)
                }
            }
        }
    }

    /// Looks every minute and reloads when the shown day has changed: no
    /// store change marks a new day, and the running entry's part moves to it.
    private func watchShownDay() async {
        var watcher = ShownDayWatcher(calendar: store.displayCalendar(), now: clock.now)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if watcher.dayChanged(calendar: store.displayCalendar(), now: clock.now), !Task.isCancelled {
                await storeChanged(.structure)
            }
        }
    }

    /// The synced start of day among `keys`: every view shows other days.
    func reloadAfterStartOfDayChange(_ keys: Set<String>) async {
        if keys.contains(SyncedSettingKey<Int>.startOfDayHour.name) {
            await storeChanged(.structure)
            await sections.activity.reload()
        }
    }

    /// Whether `change` reloads the Timer and the open sections.
    private static func reloadsSections(_ change: StoreChange) -> Bool {
        switch change {
        case .entries, .runningEntry, .structure: true
        default: false
        }
    }

    /// Reloads until no further reload was requested meanwhile.
    private func runRequestedReloads() async {
        while reloadRequested {
            reloadRequested = false
            await storeChanged(.structure)
        }
        reloadLoop = nil
    }
}
