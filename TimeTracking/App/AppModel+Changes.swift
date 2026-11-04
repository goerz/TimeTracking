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

    /// Sleeps until the running entry's next midnight, runs the pass, and
    /// repeats; with nothing running it looks again every minute.
    private func splitAtMidnights() async {
        while !Task.isCancelled {
            guard let midnight = try? await store.nextMidnightSplit() else {
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            try? await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(clock.now))))
            await checkInvariants()
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
