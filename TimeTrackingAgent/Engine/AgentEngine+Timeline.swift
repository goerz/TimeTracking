// AgentEngine+Timeline: keeping the block log one timeline, where `device`
// and synced Safari blocks only cover time the Mac's blocks leave free
// (spec_activity_tracking.md §2.8).

import Foundation
import os
import TimeTrackingCore

extension AgentEngine {
    /// The time in `[from, to]` claimed by blocks ranked above `rank`: those
    /// in the block log and, for ranks below the Mac's, the live open block
    /// up to its last attentive sample and a held short block.
    func claimed(from: Date, to: Date, above rank: Int) -> [DateInterval] {
        let zone = environment.timeZone
        let range = DateInterval(start: from, end: max(from, to))
        var result: [DateInterval] = []
        let files = MonthFileRewriter.monthFiles(
            in: logs.blocksFolder,
            fromDay: ActivityTimestamp.day(from, timeZone: zone),
            toDay: ActivityTimestamp.day(to, timeZone: zone)
        )
        for url in files {
            for block in (try? BlockLogFile(contentsOf: url))?.blocks ?? []
                where Timeline.rank(block, mac: configuration.device) > rank
            {
                let interval = DateInterval(start: block.start, end: max(block.start, block.end))
                if Timeline.overlaps(interval, [range]) {
                    result.append(interval)
                }
            }
        }
        if rank < Timeline.mac {
            if let open = blocker.open, open.lastAttentive > open.start {
                result.append(DateInterval(start: open.start, end: open.lastAttentive))
            }
            if let held = blocker.held, held.end > held.start {
                result.append(DateInterval(start: held.start, end: held.end))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// The local day `day` (`YYYY-MM-DD`) in the agent's time zone.
    func dayInterval(_ day: String, timeZone: TimeZone? = nil) -> DateInterval? {
        let zone = timeZone ?? environment.timeZone
        guard let start = ActivityTimestamp.date(day + "T00:00:00", timeZone: zone) else {
            return nil
        }
        return DateInterval(start: start, end: ActivityTimestamp.nextMidnight(after: start, timeZone: zone))
    }

    /// After a block of the Mac was written on `day`: merges the day's
    /// device events again around it and cuts it out of synced Safari blocks.
    func settleTimeline(day: String) {
        do {
            for deviceDay in try store.deviceDays(on: day) {
                try mergeDeviceDay(deviceDay)
            }
            try clipRemoteBlocks(day: day)
        } catch {
            logger.error("timeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Replaces the synced Safari blocks of `day` that overlap a Mac or
    /// device block (or the open block) by their free parts of at least
    /// `min_block`; leaves the files untouched when none overlaps.
    func clipRemoteBlocks(day: String) throws {
        guard let range = dayInterval(day) else {
            return
        }
        let claims = claimed(from: range.start, to: range.end, above: Timeline.remote)
        let mac = configuration.device
        let isClipped: (ActivityBlock) -> Bool = { block in
            block.localDay == day
                && Timeline.rank(block, mac: mac) == Timeline.remote
                && Timeline.overlaps(DateInterval(start: block.start, end: max(block.start, block.end)), claims)
        }
        let blocksFile = logs.blocksFolder.appending(path: "\(day.prefix(7)).jsonl", directoryHint: .notDirectory)
        guard ((try? BlockLogFile(contentsOf: blocksFile))?.blocks ?? []).contains(where: isClipped) else {
            return
        }
        var removed: [ActivityBlock] = []
        var detailItems: [String: [ActivityItem]] = [:]
        var contexts: [String: [String: String]] = [:]
        try logs.rewrite(fromDay: day, toDay: day) { block, detail, header in
            guard isClipped(block) else {
                return .keep
            }
            if let detail {
                detailItems[block.id] = detail.items
            } else {
                removed.append(block)
                contexts[block.id] = header
            }
            return .drop
        }
        for block in removed {
            let parts = Timeline.clipped(
                block,
                detailItems: detailItems[block.id] ?? block.items,
                outside: claims,
                minBlock: settings.blocks.minBlock
            )
            for part in parts {
                let used = Set((part.detailItems + part.block.background).map(\.context))
                let closed = ClosedBlock(
                    block: part.block,
                    detailItems: part.detailItems,
                    contexts: (contexts[block.id] ?? [:]).filter { used.contains($0.key) }
                )
                try logs.appendSummary(closed)
            }
        }
    }
}
