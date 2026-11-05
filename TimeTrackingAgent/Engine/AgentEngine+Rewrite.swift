// AgentEngine+Rewrite: the socket's rewrite commands `delete-block`,
// `forget-day`, and `reapply-exclusions` (activity_tracking.md §7.3).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// Runs a rewrite command over both logs and the samples.
    func rewrite(_ command: TrackerCommand) -> TrackerReply {
        do {
            switch command {
            case let .deleteBlock(start, end):
                return try deleteBlock(start: start, end: end)
            case let .forgetDay(day):
                try forgetDay(day)
                return .success
            case let .reapplyExclusions(from, to):
                try reapplyExclusions(fromDay: from, toDay: to)
                return .success
            case .tick, .tmuxEvent, .agentEvent:
                return .error("not a rewrite command")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// From the start of `fromDay` to the midnight after `toDay`, local time.
    private func dayRange(from fromDay: String, to toDay: String) -> Range<Date>? {
        let zone = environment.timeZone
        guard let start = ActivityTimestamp.date(fromDay + "T00:00:00", timeZone: zone),
              let last = ActivityTimestamp.date(toDay + "T00:00:00", timeZone: zone)
        else {
            return nil
        }
        return start ..< ActivityTimestamp.nextMidnight(after: last, timeZone: zone)
    }

    /// Deletes the block starting at `start` (local time) and what it was
    /// formed from, and records its time as deleted.
    private func deleteBlock(start: String, end: String?) throws -> TrackerReply {
        guard ActivityTimestamp.date(start, utcOffset: 0) != nil else {
            return .error("not a local time: \(start)")
        }
        let day = String(start.prefix(10))
        let now = environment.clock.now
        let blocks = logs.blocks(on: day)
        if let end {
            // The range the user saw: a tick may have cut it into several
            // blocks since, and all of them go.
            guard let from = ActivityTimestamp.date(start, timeZone: environment.timeZone),
                  let to = ActivityTimestamp.date(end, timeZone: environment.timeZone), to > from,
                  blocks.contains(where: { $0.start < to && $0.end > from })
            else {
                return .error("\(TrackerReply.noBlockReason) \(start)")
            }
            let followed = blocks.contains { $0.start == to }
            try forget(from: from, to: followed ? to : to.addingTimeInterval(1))
        } else if let block = blocks.first(where: { ActivityTimestamp.text($0.start, utcOffset: $0.utcOffset) == start }) {
            // A sample at the end belongs to the block that starts there.
            let followed = blocks.contains { $0.start == block.end }
            try forget(from: block.start, to: followed ? block.end : block.end.addingTimeInterval(1))
        } else if let open = openBlock, ActivityTimestamp.text(open.start, timeZone: environment.timeZone) == start {
            try forget(from: open.start, to: now.addingTimeInterval(1))
        } else {
            return .error("\(TrackerReply.noBlockReason) \(start)")
        }
        rebuild(days: [day])
        writeCurrentState()
        return .success
    }

    private func forgetDay(_ day: String) throws {
        guard let range = dayRange(from: day, to: day) else {
            return
        }
        try forget(from: range.lowerBound, to: range.upperBound)
        rebuild(days: [day])
        writeCurrentState()
    }

    /// Deletes every input of `[from, to)` and its file changes and presence transitions.
    private func forget(from: Date, to: Date) throws {
        try store.deleteTimeline(from: from, to: to)
        fileChanges.removeAll(from: from, to: to)
        transitions.removeAll { $0.time >= from && $0.time < to }
        timelineInputsChanged()
    }

    private func reapplyExclusions(fromDay: String, toDay: String) throws {
        reloadSettings()
        let rules = resolveContext().exclusions
        let decideStretch: (ActivityBackgroundStretch, [String: String]) -> StretchDecision = { stretch, contexts in
            guard stretch.localDay >= fromDay, stretch.localDay <= toDay else {
                return .keep
            }
            guard let updated = rules.reapplied(to: stretch, contexts: contexts) else {
                return .drop
            }
            return updated == stretch ? .keep : .replace(updated)
        }
        try logs.rewrite(fromDay: fromDay, toDay: toDay, decideStretch: decideStretch) { block, detail, contexts in
            guard block.localDay >= fromDay, block.localDay <= toDay else {
                return .keep
            }
            guard let newBlock = rules.reapplied(to: block, contexts: contexts) else {
                return .drop
            }
            let newDetail = detail.map { rules.reapplied(to: $0, contexts: contexts) }
            return newBlock == block && newDetail == detail ? .keep : .replace(newBlock, newDetail)
        }
        guard let range = dayRange(from: fromDay, to: toDay) else {
            return
        }
        for row in try store.rows(from: range.lowerBound, to: range.upperBound) {
            let updated = SampleRewrite.reapplied(row.sample, rules: rules)
            if updated != row.sample {
                try store.update(row.id, with: updated, utcOffset: row.utcOffset)
            }
        }
        for kind in [ExtraSampleKind.knowledge, .remote] {
            for row in try store.extraSamples(kind, from: range.lowerBound, to: range.upperBound) {
                let updated = SampleRewrite.reapplied(row.sample, rules: rules)
                if updated != row.sample {
                    try store.updateExtraSample(row.id, with: updated, utcOffset: row.utcOffset)
                }
            }
        }
        timelineInputsChanged()
    }
}
