// AgentEngine+Maintenance: retention, the Knowledge backfill, and synced
// Safari history (spec_activity_tracking.md §3.2, §4.1, §6.1, §6.2).

import Foundation
import os
import TimeTrackingCore

extension AgentEngine {
    static let purgeInterval: TimeInterval = 86_400
    static let knowledgeInterval: TimeInterval = 900
    static let syncedSafariInterval: TimeInterval = 300

    /// Runs what is due at `now`; the first tick runs everything.
    func runMaintenance(now: Date) {
        if isDue("purge", every: Self.purgeInterval, now: now) {
            // Device events are purged by `syncDeviceEvents`, off the tick.
            purge(now: now)
        }
        if isDue("knowledge", every: Self.knowledgeInterval, now: now) {
            backfillFromKnowledge(now: now)
        }
        if isDue("synced_safari", every: Self.syncedSafariInterval, now: now) {
            collectSyncedSafari(now: now)
        }
        if isDue("knowledge_check", every: Self.purgeInterval, now: now) {
            crossCheckKnowledge(now: now)
        }
    }

    /// Compares yesterday's per-app time of the samples with the Knowledge
    /// store's `/app/usage` and logs a difference over a quarter (§3.2).
    func crossCheckKnowledge(now: Date) {
        let today = ActivityTimestamp.startOfDay(now, timeZone: environment.timeZone)
        let yesterday = ActivityTimestamp.startOfDay(today.addingTimeInterval(-3600), timeZone: environment.timeZone)
        guard case let .data(apps, _, _) = environment.knowledge.read(from: yesterday, to: today) else {
            return
        }
        let knowledgeSeconds = apps.reduce(0.0) { total, app in
            total + max(0, min(app.end, today).timeIntervalSince(max(app.start, yesterday)))
        }
        let attentive = ((try? store.rows(from: yesterday, to: today)) ?? []).filter(\.sample.isAttentive)
        let sampleSeconds = Double(attentive.count) * Self.tickInterval
        let larger = max(knowledgeSeconds, sampleSeconds)
        guard larger > 0 else {
            return
        }
        let difference = abs(knowledgeSeconds - sampleSeconds) / larger
        if difference > 0.25 {
            logger.notice("Knowledge cross-check: app time differs by \(Int(difference * 100), privacy: .public)% from the samples")
        }
    }

    func isDue(_ key: String, every interval: TimeInterval, now: Date) -> Bool {
        if let last = lastMaintenance[key], now.timeIntervalSince(last) < interval, now >= last {
            return false
        }
        lastMaintenance[key] = now
        return true
    }

    /// Deletes samples older than 90 days.
    func purge(now: Date) {
        do {
            try store.purge(before: now.addingTimeInterval(-SampleStore.retention))
        } catch {
            logger.error("purge: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Knowledge store

    /// The Knowledge watermark: everything before it was considered.
    static let knowledgeWatermarkKey = "knowledge.watermark"
    /// How far back the first backfill looks.
    static let knowledgeLookback: TimeInterval = 7 * 86_400
    /// How far before its watermark a source is read again: data that
    /// arrives late (an app's usage written when it quits, Safari visits
    /// synced hours later) carries times before the watermark. The samples
    /// of the range are replaced, so reading again changes nothing else.
    static let lateDataWindow: TimeInterval = 86_400

    /// Reconstructs samples for the periods since the watermark in which
    /// the agent took no sample, from `/app/usage`, stores them, and forms
    /// the days they touch again.
    func backfillFromKnowledge(now: Date) {
        let watermark = (try? store.date(Self.knowledgeWatermarkKey)) ?? now.addingTimeInterval(-Self.knowledgeLookback)
        let from = max(min(watermark, now.addingTimeInterval(-Self.lateDataWindow)), now.addingTimeInterval(-Self.knowledgeLookback))
        // The current open stretch is the live agent's; stop one tick before now.
        let until = now.addingTimeInterval(-Self.tickInterval)
        guard until > from else {
            return
        }
        let read = environment.knowledge.read(from: from, to: until)
        guard case let .data(apps, _, displayOff) = read else {
            if case let .unavailable(reason) = read {
                health.set(.knowledge, .off, reason)
            }
            return
        }
        health.set(.knowledge, .active)
        let rules = resolveContext().exclusions
        var days = Set<String>()
        for gap in downPeriods(from: from, to: until) {
            let samples = KnowledgeBackfill.samples(apps: apps, displayOff: displayOff, in: gap, rules: rules, interval: Self.tickInterval)
            do {
                try store.replaceExtraSamples(
                    .knowledge,
                    from: gap.start,
                    to: gap.end.addingTimeInterval(1),
                    with: samples.map { (sample: $0, device: configuration.device) }
                ) { environment.timeZone.secondsFromGMT(for: $0) }
            } catch {
                logger.error("knowledge samples: \(error.localizedDescription, privacy: .public)")
            }
            if !samples.isEmpty {
                days.insert(day(of: gap.start))
                days.insert(day(of: gap.end))
            }
        }
        try? store.setDate(until, for: Self.knowledgeWatermarkKey)
        rebuild(days: days)
    }

    /// Forms `days` again after their inputs changed, today last.
    func rebuild(days: Set<String>) {
        guard !days.isEmpty else {
            return
        }
        timelineInputsChanged()
        let today = day(of: environment.clock.now)
        for day in days.sorted() where day < today {
            rebuild(day: day)
        }
        if days.contains(today) {
            rebuildToday()
        }
    }

    /// The stretches of `[from, to]` without samples longer than `idle_close`.
    func downPeriods(from: Date, to: Date) -> [DateInterval] {
        let times = (try? store.times(from: from, to: to)) ?? []
        var result: [DateInterval] = []
        var previous = from
        for time in times + [to] {
            if time.timeIntervalSince(previous) > settings.blocks.idleClose {
                result.append(DateInterval(start: previous.addingTimeInterval(1), end: time.addingTimeInterval(-1)))
            }
            previous = time
        }
        return result
    }

    // MARK: Synced Safari history

    static let syncedSafariWatermarkKey = "synced_safari.watermark"

    /// Stores Safari visits synced from other devices as samples (§6.1)
    /// and forms the days they touch again.
    func collectSyncedSafari(now: Date) {
        guard settings.devices.syncedSafariHistory, environment.history.canReadSafari else {
            return
        }
        syncedSafari.poll(history: environment.history, now: now)
        let watermark = (try? store.date(Self.syncedSafariWatermarkKey)) ?? now.addingTimeInterval(-Self.lateDataWindow)
        let from = min(watermark, now.addingTimeInterval(-Self.lateDataWindow))
        // Visits younger than the gap may still belong to an unfinished run.
        let until = now.addingTimeInterval(-SyncedSafariCollector.gap)
        guard until > from, let visits = environment.history.safariVisits(from: from, to: until, origin: 1) else {
            return
        }
        let samples = syncedSafari.samples(visits: visits, context: resolveContext())
        let known = Set(((try? store.extraSamples(.remote, from: from, to: until)) ?? []).map(\.sample.time))
        do {
            try store.replaceExtraSamples(.remote, from: from, to: until, with: samples) { date in
                environment.timeZone.secondsFromGMT(for: date)
            }
        } catch {
            logger.error("synced Safari: \(error.localizedDescription, privacy: .public)")
        }
        try? store.setDate(until, for: Self.syncedSafariWatermarkKey)
        // Only the days that gained or lost a visit form again.
        let changed = Set(samples.map(\.sample.time)).symmetricDifference(known)
        rebuild(days: Set(changed.map { day(of: $0) }))
    }
}
