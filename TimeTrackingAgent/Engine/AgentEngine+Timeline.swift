// AgentEngine+Timeline: forming a day's blocks from everything stored for
// it and rewriting the day in both logs (spec_activity_tracking.md §2.8,
// §4.2, §4.3).

import Foundation
import os
import TimeTrackingCore

/// A day's timeline inputs, kept between ticks; the engine appends each new
/// sample and drops the cache when any other input of the day changes.
struct TimelineCache {
    var day: String
    var inputs: TimelineInputs
    /// The Blocker part way through the day, so a tick runs only the newest steps.
    var checkpoint: Timeline.Checkpoint?

    mutating func append(_ sample: Sample) {
        inputs.mac.append(sample)
    }
}

extension AgentEngine {
    /// The local date of `date` in the agent's time zone.
    func day(of date: Date) -> String {
        ActivityTimestamp.day(date, timeZone: environment.timeZone)
    }

    /// The local day `day` (`YYYY-MM-DD`) in the agent's time zone.
    func dayInterval(_ day: String) -> DateInterval? {
        let zone = environment.timeZone
        guard let start = ActivityTimestamp.date(day + "T00:00:00", timeZone: zone) else {
            return nil
        }
        return DateInterval(start: start, end: ActivityTimestamp.nextMidnight(after: start, timeZone: zone))
    }

    /// Forms today's blocks again; after midnight it first closes the
    /// previous day. `final` (agent shutdown) closes the open block too.
    func rebuildToday(final: Bool = false) {
        let today = day(of: environment.clock.now)
        if let previous = rebuiltDay, previous != today {
            rebuild(day: previous)
        }
        rebuiltDay = today
        rebuild(day: today, final: final)
        let cutoff = environment.clock.now.addingTimeInterval(-2 * 86_400)
        if let kept = transitions.last(where: { $0.time < cutoff }) {
            transitions.removeAll { $0.time < cutoff }
            transitions.insert(kept, at: 0)
        }
    }

    /// Forms the blocks of `day` from its stored inputs and replaces the
    /// day's lines in both logs when they changed. A past day is closed at
    /// its end, with the next `idle_close` read so a block open at midnight
    /// ends there; today's last block stays open (`current.json`) unless
    /// `final`.
    func rebuild(day: String, final: Bool = false) {
        guard let range = dayInterval(day) else {
            return
        }
        let now = environment.clock.now
        let isToday = day == self.day(of: now)
        let end = isToday ? now.addingTimeInterval(1) : range.end.addingTimeInterval(settings.blocks.idleClose)
        let inputs = timelineInputs(day: day, from: range.start, to: end)
        let cached = timelineCache?.day == day
        let (result, checkpoint) = Timeline.run(
            inputs,
            settings: settings.blocks,
            timeZone: environment.timeZone,
            mac: configuration.device,
            flush: !isToday || final,
            until: now,
            checkpoint: cached ? timelineCache?.checkpoint : nil
        )
        if cached {
            timelineCache?.checkpoint = checkpoint
        }
        if isToday {
            openBlock = result.open.flatMap { range.contains($0.start) ? $0 : nil }
        }
        do {
            try write(day: day, result.closed.filter { $0.block.localDay == day })
        } catch {
            logger.error("block log: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the cached inputs, after another input of a day changed.
    func timelineInputsChanged() {
        timelineCache = nil
    }

    /// The inputs of `day` within `[from, to)`: today's from the cache.
    private func timelineInputs(day: String, from: Date, to: Date) -> TimelineInputs {
        if let cache = timelineCache, cache.day == day {
            return cache.inputs
        }
        var inputs = TimelineInputs()
        inputs.mac = ((try? store.rows(from: from, to: to)) ?? []).map(\.sample)
        inputs.reconstructed = ((try? store.extraSamples(.knowledge, from: from, to: to)) ?? []).map(\.sample)
        let remote = ((try? store.extraSamples(.remote, from: from, to: to)) ?? []).map { (sample: $0.sample, device: $0.device) }
        inputs.others = Timeline.remoteStretches(remote)
        let merger = DeviceEventMerger(settings: settings, exclusions: resolveContext().exclusions)
        for deviceDay in (try? store.deviceDays(on: day)) ?? [] {
            let events = (try? store.deviceEvents(device: deviceDay.device, day: deviceDay.day)) ?? []
            let zone = TimeZone(secondsFromGMT: deviceDay.utcOffset) ?? environment.timeZone
            let (stretches, closers) = merger.stretches(events, device: deviceDay.device, timeZone: zone)
            inputs.others += stretches
            inputs.closers += closers
        }
        inputs.suppressed = (try? store.suppressed(from: from, to: to)) ?? []
        if day == self.day(of: environment.clock.now) {
            timelineCache = TimelineCache(day: day, inputs: inputs)
        }
        return inputs
    }

    /// Replaces the blocks of `day` by `closed` unless they are the same;
    /// an unchanged block keeps its detail line, a new or changed one gets
    /// the detail entries of the old lines within its range and its own.
    private func write(day: String, _ closed: [ClosedBlock]) throws {
        let existing = logs.blocks(on: day)
        guard existing != closed.map(\.block) else {
            return
        }
        let unchanged = Set(existing)
        let old = logs.detailEntries(on: day)
        let oldDetails = Dictionary(old.compactMap { entry in entry.detail.map { (entry.block.id, $0) } }) { first, _ in first }
        let pool = DetailPool(old.compactMap(\.detail))
        var previousEnd = dayInterval(day)?.start ?? closed.first?.block.start ?? .distantPast
        var written: [(block: ClosedBlock, detail: ActivityBlockDetail)] = []
        for block in closed {
            if unchanged.contains(block.block), var detail = oldDetails[block.block.id] {
                detail.items = block.detailItems
                written.append((block, detail))
            } else {
                written.append((block, detail(for: block, since: previousEnd, pool: pool)))
            }
            previousEnd = block.block.end
        }
        try logs.replaceDay(day, with: written)
    }
}

/// The timestamped detail entries of a day's old detail lines, handed to
/// the blocks that now cover their times.
struct DetailPool {
    var urls: [ActivityURLVisit] = []
    var files: [ActivityFileChange] = []
    var presence: [ActivityPresenceTransition] = []
    var dwell: [ActivityDwell] = []

    init(_ details: [ActivityBlockDetail]) {
        for detail in details {
            urls += detail.urls
            files += detail.files
            presence += detail.presence
            dwell += detail.dwell
        }
    }
}
