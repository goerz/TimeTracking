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

    /// Reconstructs `knowledge` blocks for the periods since the watermark
    /// in which the agent took no sample, from `/app/usage`.
    func backfillFromKnowledge(now: Date) {
        let watermark = (try? store.date(Self.knowledgeWatermarkKey)) ?? now.addingTimeInterval(-Self.knowledgeLookback)
        let from = max(watermark, now.addingTimeInterval(-Self.knowledgeLookback))
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
        let gaps = downPeriods(from: from, to: until)
        let rules = resolveContext().exclusions
        var knowledgeBlocker = Blocker(
            settings: settings.blocks,
            timeZone: environment.timeZone,
            device: configuration.device,
            source: .knowledge
        )
        for gap in gaps {
            var closed: [ClosedBlock] = []
            for sample in KnowledgeBackfill
                .samples(apps: apps, displayOff: displayOff, in: gap, rules: rules, interval: Self.tickInterval)
            {
                closed += knowledgeBlocker.add(sample)
            }
            closed += knowledgeBlocker.flush()
            let written = ClosedBlock.resolved(closed)
            for block in written {
                appendSummary(block, kind: "knowledge")
            }
            for day in Set(written.map(\.block.localDay)).sorted() {
                settleTimeline(day: day)
            }
        }
        try? store.setDate(until, for: Self.knowledgeWatermarkKey)
    }

    /// Appends a block formed off the tick (`kind` names it in the log).
    private func appendSummary(_ closed: ClosedBlock, kind: String) {
        do {
            try logs.appendSummary(closed)
        } catch {
            logger.error("\(kind, privacy: .public) block: \(error.localizedDescription, privacy: .public)")
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

    /// Forms `remote` blocks from Safari visits synced from other devices
    /// (§6.1), in the time no Mac or device block claims (§2.8).
    func collectSyncedSafari(now: Date) {
        guard settings.devices.syncedSafariHistory, environment.history.canReadSafari else {
            return
        }
        syncedSafari.poll(history: environment.history, now: now)
        let watermark = (try? store.date(Self.syncedSafariWatermarkKey)) ?? now.addingTimeInterval(-86_400)
        // Visits younger than the gap may still belong to an open block.
        let until = now.addingTimeInterval(-SyncedSafariCollector.gap)
        guard until > watermark, let visits = environment.history.safariVisits(from: watermark, to: until, origin: 1) else {
            return
        }
        let context = resolveContext()
        let claims = claimed(from: watermark, to: until, above: Timeline.remote)
        for closed in syncedSafari.blocks(visits: visits, context: context, timeZone: environment.timeZone, claimed: claims) {
            appendSummary(closed, kind: "synced Safari")
        }
        try? store.setDate(until, for: Self.syncedSafariWatermarkKey)
    }
}
