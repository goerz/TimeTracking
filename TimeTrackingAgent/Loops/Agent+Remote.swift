// Agent+Remote: the remote activity loop: DeviceEvents from CloudKit
// stored and converted per device-date, then the synced Safari visits
// (activity_tracking.md §2.5, §6).

import Foundation
import os
import TimeTrackingCore

extension Agent {
    /// One remote cycle: fetches the DeviceEvents added since the last
    /// fetch (outside every step, since CloudKit takes its time), then, as
    /// steps, stores them with the new token, redoes each pending
    /// device-date, and reads the synced Safari visits. One cycle at a
    /// time: `runDueWork` sets `fetching` before it starts one.
    func fetchDeviceEvents() async {
        guard let source = deviceEvents else {
            health.set(.deviceEvents, .off, "iCloud is not available; iPhone and iPad activity doesn't reach this Mac")
            finishRemoteCycle()
            return
        }
        let batch: DeviceEventBatch
        do {
            batch = try await source.events(since: store.meta(.cloudKitToken).map(ChangeToken.init(data:)))
            if batch.unreadable > 0 {
                logger.error("device events: \(batch.unreadable) records of another app version skipped")
                health.set(.deviceEvents, .fallback, SourceID.otherAppVersionReason)
            } else {
                health.set(.deviceEvents, .active)
            }
        } catch {
            logger.error("device events: \(error.localizedDescription, privacy: .public)")
            health.set(.deviceEvents, .fallback, "Couldn't reach iCloud; trying again in 5 minutes")
            finishRemoteCycle()
            return
        }
        queue.enqueue(
            "device-events-\(UUID())",
            cancel: { [self] in fetching = false },
            run: { [self] in
                do {
                    try store.storeDeviceEvents(batch.events, token: batch.token.data, rules: rules)
                } catch {
                    logger.error("device events: \(error.localizedDescription, privacy: .public)")
                }
                finishRemoteCycle()
            }
        )
    }

    /// The cycle's last steps: the pending redos, then the synced visits.
    private func finishRemoteCycle() {
        queuePendingRedos()
        queue.enqueue("synced-safari") { [self] in readSyncedSafari() }
        fetching = false
    }

    /// Queues a redo step for every pending device-date.
    func queuePendingRedos() {
        for deviceDay in (try? store.meta(.pendingRemoteDays)) ?? [] {
            queueRedo(deviceDay)
        }
    }

    /// A step that redoes one device-date; when that changes what is on at
    /// the date's end, the next date (queued in `meta` by the redo) follows.
    private func queueRedo(_ deviceDay: DeviceDay) {
        queue.enqueue("device-day-\(deviceDay.deviceID)-\(deviceDay.day)") { [self] in
            do {
                let converter = DeviceEventConverter(
                    maxBlock: settings.blocks.maxBlock,
                    urls: taker.workspaces.urlWorkspaces(settings: settings.workspaces)
                )
                let today = today
                if try store.redo(deviceDay, converter: converter, today: today, rules: rules) {
                    let next = DeviceDay(deviceID: deviceDay.deviceID, day: deviceDay.day.adding(days: 1))
                    if next.day <= today {
                        queueRedo(next)
                    }
                }
            } catch {
                logger.error("device-date \(deviceDay.day.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
