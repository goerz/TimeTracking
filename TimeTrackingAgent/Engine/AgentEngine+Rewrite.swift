// AgentEngine+Rewrite: the socket's rewrite commands `delete-block`,
// `forget-day`, and `reapply-exclusions` (spec_activity_tracking.md §7.3).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// Runs a rewrite command over both logs and the samples.
    func rewrite(_ command: TrackerCommand) -> TrackerReply {
        do {
            switch command {
            case let .deleteBlock(device, start):
                return try deleteBlock(device: device, start: start)
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

    private var logFolders: [URL] {
        [logs.blocksFolder, logs.detailFolder]
    }

    private func deleteBlock(device: String, start: String) throws -> TrackerReply {
        guard ActivityTimestamp.date(start, utcOffset: 0) != nil else {
            return .error("not a local time: \(start)")
        }
        var removed: [ActivityBlock] = []
        for folder in logFolders {
            for url in MonthFileRewriter.monthFiles(in: folder, fromDay: String(start.prefix(10)), toDay: String(start.prefix(10))) {
                removed += try MonthFileRewriter.rewrite(url) { block, _, _ in
                    block.device == device && ActivityTimestamp.text(block.start, utcOffset: block.utcOffset) == start ? .drop : .keep
                }
            }
        }
        if let open = blocker.open, device == configuration.device,
           ActivityTimestamp.text(open.start, timeZone: environment.timeZone) == start
        {
            try store.delete(from: open.start, to: environment.clock.now.addingTimeInterval(1))
            blocker.discardOpenBlock()
            writeCurrentState()
            return .success
        }
        guard let block = removed.first else {
            return .error("no block of \(device) at \(start)")
        }
        if device == configuration.device {
            try store.delete(from: block.start, to: block.end.addingTimeInterval(1))
        }
        return .success
    }

    private func forgetDay(_ day: String) throws {
        for folder in logFolders {
            for url in MonthFileRewriter.monthFiles(in: folder, fromDay: day, toDay: day) {
                try MonthFileRewriter.rewrite(url) { block, _, _ in block.localDay == day ? .drop : .keep }
            }
        }
        guard let start = ActivityTimestamp.date(day + "T00:00:00", timeZone: environment.timeZone) else {
            return
        }
        let end = ActivityTimestamp.nextMidnight(after: start, timeZone: environment.timeZone)
        try store.delete(from: start, to: end)
        fileChanges.removeAll(from: start, to: end)
        transitions.removeAll { $0.time >= start && $0.time < end }
        if let open = blocker.open, open.start >= start, open.start < end {
            blocker.discardOpenBlock()
        }
        writeCurrentState()
    }

    private func reapplyExclusions(fromDay: String, toDay: String) throws {
        monitor.reload()
        let rules = resolveContext().exclusions
        for folder in logFolders {
            for url in MonthFileRewriter.monthFiles(in: folder, fromDay: fromDay, toDay: toDay) {
                try MonthFileRewriter.rewrite(url) { block, detail, contexts in
                    guard block.localDay >= fromDay, block.localDay <= toDay else {
                        return .keep
                    }
                    guard let newBlock = rules.reapplied(to: block, contexts: contexts) else {
                        return .drop
                    }
                    let newDetail = detail.map { rules.reapplied(to: $0, contexts: contexts) }
                    return newBlock == block && newDetail == detail ? .keep : .replace(newBlock, newDetail)
                }
            }
        }
        guard let start = ActivityTimestamp.date(fromDay + "T00:00:00", timeZone: environment.timeZone),
              let last = ActivityTimestamp.date(toDay + "T00:00:00", timeZone: environment.timeZone)
        else {
            return
        }
        let end = ActivityTimestamp.nextMidnight(after: last, timeZone: environment.timeZone)
        for row in try store.rows(from: start, to: end) {
            let updated = SampleRewrite.reapplied(row.sample, rules: rules)
            if updated != row.sample {
                try store.update(row.id, with: updated, utcOffset: row.utcOffset)
            }
        }
    }
}

/// Applies the current exclusions to a stored sample.
nonisolated enum SampleRewrite {
    static func reapplied(_ sample: Sample, rules: ExclusionRules) -> Sample {
        var result = sample
        if !sample.bundleID.isEmpty, rules.excludesApp(sample.bundleID) {
            return Sample(time: sample.time, state: sample.state, event: sample.event)
        }
        result.primary = sample.primary.flatMap { reapplied($0, bundleID: sample.bundleID, rules: rules) }
        result.secondaries = sample.secondaries.compactMap { reapplied($0, bundleID: $0.app, rules: rules) }
        if rules.excludesDomain(sample.url) {
            result.url = ""
            result.title = ""
        } else if rules.isPrivateDomain(sample.url), let components = URLComponents(string: sample.url), let host = components.host {
            result.url = "\(components.scheme ?? "https")://\(host)"
            result.title = ""
        }
        if rules.excludesTitle(result.title) {
            result.title = ""
        }
        if result.primary?.subject == ExclusionRules.privateMarker {
            result.url = ""
            result.title = ""
        }
        return result
    }

    static func reapplied(_ item: SampleItem, bundleID: String, rules: ExclusionRules) -> SampleItem? {
        let recorded = ActivityItem(context: item.context, subject: item.subject, detail: item.detail, seconds: 0)
        guard let kept = rules.reapplied(to: recorded, bundleIdentifier: bundleID) else {
            return nil
        }
        var result = item
        result.context = kept.context
        result.subject = kept.subject
        result.detail = kept.detail
        if kept.context != item.context {
            result.groupKey = kept.context
        } else if kept.subject == ExclusionRules.privateMarker, kept.detail == ExclusionRules.privateMarker,
                  !item.context.hasPrefix("tmux:")
        {
            result.groupKey = ExclusionRules.privateGroupKey
        } else if kept.subject == ExclusionRules.privateMarker {
            result.groupKey = item.context.hasPrefix("tmux:") ? item.groupKey : item.context
        } else if kept.subject != item.subject, rules.isPrivateDomain(kept.subject) {
            result.groupKey = kept.subject
        }
        return result
    }
}
