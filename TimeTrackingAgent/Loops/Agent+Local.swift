// Agent+Local: the local activity loop's other steps: Samples rebuilt from
// app usage for the time the agent didn't run, and the daily drop
// (activity_tracking.md §2.4).

import Foundation
import os
import TimeTrackingCore

extension Agent {
    /// How far back app usage is read again, because macOS writes it late.
    static let appUsageLookback: TimeInterval = 86_400
    /// A Sample every 30 seconds through each app interval.
    static let appUsageStep: TimeInterval = 30

    /// Fills every stretch longer than `idle_close` without a live Sample,
    /// from where app usage was last read (at least 24 hours back, never
    /// before `fill_after`) to now, with one `appUsage` Sample every 30
    /// seconds through each app interval of `knowledgeC.db` there.
    func fillGaps() throws {
        guard let fillAfter = try store.meta(.fillAfter) else {
            return
        }
        let now = environment.clock.now
        let readUntil = try store.meta(.appUsageReadUntil) ?? fillAfter
        let from = max(fillAfter, min(readUntil, now - Self.appUsageLookback))
        guard now > from else {
            return
        }
        let apps: [KnowledgeAppInterval]
        switch environment.knowledge.read(from: from, to: now) {
        case let .unavailable(reason):
            health.set(.knowledge, .off, reason)
            return
        case let .data(intervals, _, _):
            health.set(.knowledge, .active)
            apps = intervals
        }
        let live = try store.liveTimes(in: DateInterval(start: from, end: now))
        for gap in Self.gaps(between: live, from: from, to: now, longerThan: settings.blocks.idleClose) {
            let samples = apps.flatMap { interval in
                stride(
                    from: max(interval.start, gap.start).timeIntervalSince1970.rounded(.up),
                    to: min(interval.end, gap.end).timeIntervalSince1970,
                    by: Self.appUsageStep
                )
                .map { time in
                    Sample(
                        time: Date(timeIntervalSince1970: time),
                        deviceID: configuration.macDeviceID,
                        source: .appUsage,
                        state: .active,
                        foreground: ActivityItem(app: environment.appName(interval.bundleID), appID: interval.bundleID)
                    )
                }
            }
            try store.replace(
                SampleSelection(range: gap, deviceID: configuration.macDeviceID, sources: [.appUsage]),
                with: samples,
                rules: rules
            )
        }
        try store.setMeta(.appUsageReadUntil, now)
    }

    /// The stretches longer than `minimum` without a live Sample in
    /// `[from, to)`, each starting where the last Sample's time ends.
    static func gaps(between times: [Date], from: Date, to: Date, longerThan minimum: TimeInterval) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var covered = from
        for time in times + [to] {
            if time.timeIntervalSince(covered) > minimum {
                gaps.append(DateInterval(start: covered, end: time))
            }
            covered = max(covered, time == to ? to : time + tickInterval)
        }
        return gaps
    }

    /// The daily drop: the cutoff one day toward today − 90 days, then the
    /// stored DeviceEvents before it; those in CloudKit are deleted outside
    /// the step, since CloudKit takes its time.
    func dropOldData() {
        do {
            guard try store.dropOldSamples(today: today, rules: rules) != nil, let cutoff = try store.meta(.cutoffDay) else {
                return
            }
            let start = try store.boundaries(rules: rules).start(of: cutoff)
            try store.deleteDeviceEvents(before: start)
            if let deviceEvents {
                Task { [logger] in
                    do {
                        try await deviceEvents.purge(before: start)
                    } catch {
                        logger.error("purging device events: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            logger.error("daily drop: \(error.localizedDescription, privacy: .public)")
        }
    }
}
