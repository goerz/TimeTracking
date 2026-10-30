// AgentEngine+Devices: the Devices module: fetching iPhone and iPad events
// and merging them into `device` blocks (spec_activity_tracking.md §2.3,
// §6.2, TRK-26, TRK-28).

import Foundation
import os
import TimeTrackingCore

extension AgentEngine {
    /// How often the runner fetches (no push subscription: the fallback of §2.3).
    static let deviceFetchInterval: TimeInterval = 300
    static let deviceTokenKey = "device_events.token"

    /// Fetches the events since the last fetch, stores them, and merges
    /// every device-day they touch again; once a day deletes events (here
    /// and in CloudKit) older than 90 days.
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
            for day in touched.sorted() {
                try mergeDeviceDay(day)
            }
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

    /// Replaces the `device` blocks of `day` in both logs by the merge of
    /// its stored events; leaves the files untouched when nothing changed.
    func mergeDeviceDay(_ day: DeviceDay) throws {
        let events = try store.deviceEvents(device: day.device, day: day.day)
        let zone = TimeZone(secondsFromGMT: day.utcOffset) ?? environment.timeZone
        let context = resolveContext()
        let merger = DeviceEventMerger(settings: settings, exclusions: context.exclusions)
        let merged = merger.blocks(events, device: day.device, timeZone: zone)
        let isDeviceDay: (ActivityBlock) -> Bool = { block in
            block.source == .device && block.device == day.device && block.localDay == day.day
        }
        let month = String(day.day.prefix(7))
        let blocksFile = logs.blocksFolder.appending(path: "\(month).jsonl", directoryHint: .notDirectory)
        let existing = ((try? BlockLogFile(contentsOf: blocksFile))?.entries ?? []).map(\.block).filter(isDeviceDay)
        let lines: ([ActivityBlock]) -> [String] = { $0.map { BlockLogLine.block($0, detail: nil).jsonText } }
        guard lines(existing) != lines(merged.map(\.block)) else {
            return
        }
        try logs.rewrite(fromDay: day.day, toDay: day.day) { block, _, _ in isDeviceDay(block) ? .drop : .keep }
        for closed in merged {
            try logs.appendSummary(closed)
        }
    }
}
