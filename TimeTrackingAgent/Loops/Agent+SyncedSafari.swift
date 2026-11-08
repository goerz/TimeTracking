// Agent+SyncedSafari: the remote activity loop's synced Safari visits,
// re-read for the last 24 hours on every pass (activity_tracking.md §6.1).

import Foundation
import os
import TimeTrackingCore

extension Agent {
    /// With `synced_safari_history` on: reads `CloudTabs.db` into the
    /// remembered tab gains, then replaces the `safariHistory` Samples of
    /// the last 24 hours with the synced visits of that time. Off, neither
    /// database is opened.
    func readSyncedSafari() {
        guard settings.devices.syncedSafariHistory else {
            return
        }
        let history = environment.history
        let now = environment.clock.now
        let range = DateInterval(start: now - SyncedSafari.lookback, end: now)
        // A run reaching into the range from before it keeps its device.
        guard let visits = history.safariVisits(from: range.start - SyncedSafari.lookback, to: now, origin: 1),
              let devices = history.cloudTabs()
        else {
            health.set(.syncedSafari, .off, SourceID.noSyncedSafariReason)
            return
        }
        do {
            let ids = try deviceIDs(byName: store.meta(.deviceNames) ?? [:])
            var tabs: [String: Set<String>] = [:]
            for device in devices {
                if let id = ids[device.name] {
                    tabs[id, default: []].formUnion(device.urls)
                }
            }
            let memory = try (store.meta(.cloudTabs) ?? .empty).reading(tabs, at: now)
            try store.setMeta(.cloudTabs, memory)
            let samples = SyncedSafari.samples(
                visits: visits.map { SyncedVisit(time: $0.time, url: $0.url, title: $0.title) },
                gains: memory.gains,
                urls: taker.workspaces.urlWorkspaces(settings: settings.workspaces)
            )
            try store.replace(SampleSelection(range: range, sources: [.safariHistory]), with: samples, rules: rules)
            health.set(.syncedSafari, .active)
        } catch {
            logger.error("synced Safari: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The iOS devices' ids by their latest names.
    private func deviceIDs(byName names: [String: String]) -> [String: String] {
        Dictionary(names.map { ($0.value, $0.key) }, uniquingKeysWith: { first, second in min(first, second) })
    }
}
