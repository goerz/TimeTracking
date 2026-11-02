// AgentEngine+Devices: the Devices module: fetching iPhone and iPad events
// into the user's timeline (spec_activity_tracking.md §2.3, §2.8, §6.2,
// TRK-26, TRK-28).

import Foundation
import os
import TimeTrackingCore

extension AgentEngine {
    /// How often the runner fetches (no push subscription: the fallback of §2.3).
    static let deviceFetchInterval: TimeInterval = 300
    static let deviceTokenKey = "device_events.token"

    /// Fetches the events since the last fetch, stores them, and forms
    /// every day they touch again; once a day deletes events (here and in
    /// CloudKit) older than 90 days.
    func syncDeviceEvents(now: Date) async {
        guard let deviceEvents else {
            health.set(.deviceEvents, .off, "iCloud is not available; iPhone and iPad activity doesn't reach this Mac")
            writeCurrentState()
            return
        }
        let token = (try? store.value(Self.deviceTokenKey)).flatMap { Data(base64Encoded: $0) }.map(ChangeToken.init(data:))
        do {
            let (events, next) = try await deviceEvents.events(since: token)
            let zone = environment.timeZone
            let touched = try store.insertDeviceEvents(events) { zone.secondsFromGMT(for: $0) }
            rebuild(days: Set(touched.map(\.day)))
            try store.setValue(next.data.base64EncodedString(), for: Self.deviceTokenKey)
            health.set(.deviceEvents, .active)
        } catch {
            health.set(.deviceEvents, .fallback, "Couldn't reach iCloud; trying again in 5 minutes")
            logger.error("device events: \(error.localizedDescription, privacy: .public)")
        }
        if isDue("device_purge", every: Self.purgeInterval, now: now) {
            let cutoff = now.addingTimeInterval(-SampleStore.retention)
            try? store.purgeDeviceEvents(before: cutoff)
            do {
                try await deviceEvents.purge(before: cutoff)
            } catch {
                logger.error("device event purge: \(error.localizedDescription, privacy: .public)")
            }
        }
        writeCurrentState()
    }
}
