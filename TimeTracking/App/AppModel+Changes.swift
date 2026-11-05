// AppModel+Changes: loading at launch, following the store's changes, and
// the invariant pass at midnight (spec_timer.md §2; spec_data_and_sync.md
// §1.5, §7; spec_menubar.md §5).

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
        midnightTask = Task { [weak self] in
            await self?.splitAtMidnights()
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

    /// The invariant pass (spec_data_and_sync.md §1.5): splits a running
    /// entry that crossed midnight. Runs at each midnight of the running
    /// entry, on wake, and on a clock or time zone change; its changes
    /// arrive as store changes.
    func checkInvariants() async {
        do {
            try await store.checkInvariants()
        } catch {
            Logging.logger(category: "App").error("Invariant pass: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sleeps until the running entry's next midnight or the next shown
    /// day, runs the pass, reloads (its part moves to the new day even when
    /// nothing is stored), and repeats; with nothing running it looks again
    /// every minute and reloads when the shown day has changed.
    private func splitAtMidnights() async {
        var watcher = ShownDayWatcher(calendar: store.displayCalendar(), now: clock.now)
        while !Task.isCancelled {
            guard let midnight = try? await store.nextRunningDayChange() else {
                try? await Task.sleep(for: .seconds(60))
                if watcher.dayChanged(calendar: store.displayCalendar(), now: clock.now), !Task.isCancelled {
                    await storeChanged(.structure)
                }
                continue
            }
            try? await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(clock.now))))
            await checkInvariants()
            _ = watcher.dayChanged(calendar: store.displayCalendar(), now: clock.now)
            if !Task.isCancelled {
                await storeChanged(.structure)
            }
        }
    }

    /// The synced Midnight among `keys`: every view shows other days.
    func reloadAfterMidnightChange(_ keys: Set<String>) async {
        if keys.contains(SyncedSettingKey<Int>.midnightHour.name) {
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
