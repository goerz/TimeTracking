// Agent+Requests: the agent's socket: hook events that take a Sample, and
// the requests that delete or re-filter (activity_tracking.md §2.6, §3.1, §7.3).

import Foundation
import TimeTrackingCore

extension Agent {
    /// Answers one line of the socket: `ok` or `error <reason>`. Hook
    /// events ask for a Sample and answer at once; requests run as a step,
    /// between two passes of the loops, and answer when done, or that the
    /// tracker is stopping.
    func handle(line: String) async -> String {
        let command: TrackerCommand
        do {
            command = try TrackerCommand.parse(line)
        } catch {
            return TrackerReply.error("\(error)").line
        }
        switch command {
        case .tmuxEvent:
            taker.lastEvents[.tmuxEvents] = environment.clock.now
            queue.requestTick()
            return TrackerReply.success.line
        case .agentEvent:
            taker.lastEvents[.agentEvents] = environment.clock.now
            queue.requestTick()
            return TrackerReply.success.line
        case .deleteBlock, .forgetDay, .reapplyExclusions:
            let stopping = TrackerReply.error(TrackerReply.stoppingReason).line
            return await withCheckedContinuation { continuation in
                queue.enqueue(
                    "request-\(UUID())",
                    cancel: { continuation.resume(returning: stopping) },
                    run: { [self] in continuation.resume(returning: perform(command).line) }
                )
            }
        }
    }

    /// Runs a request (§2.6).
    func perform(_ command: TrackerCommand) -> TrackerReply {
        do {
            switch command {
            case let .deleteBlock(start, end):
                guard let from = ActivityTimestamp.parseWithOffset(start)?.date, let to = ActivityTimestamp.parseWithOffset(end)?.date,
                      from < to
                else {
                    return .error("not a time range: \(start) \(end)")
                }
                return try delete(DateInterval(start: from, end: to), named: start)
            case let .forgetDay(text):
                guard let day = TrackingDay(text) else {
                    return .error("not a date: \(text)")
                }
                let boundaries = try store.boundaries(rules: rules)
                return try delete(
                    DateInterval(start: boundaries.start(of: day), end: boundaries.start(of: day.adding(days: 1))),
                    named: text
                )
            case let .reapplyExclusions(from, to):
                guard let first = TrackingDay(from), let last = TrackingDay(to), first <= last else {
                    return .error("not a date range: \(from) \(to)")
                }
                return try reapplyExclusions(first ... last)
            case .tmuxEvent, .agentEvent:
                return .success
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Deletes the Samples of `range` up to now and adds it to the deleted
    /// ranges; on frozen dates removes the blocks there from the date
    /// files. Only the recording Mac deletes: another Mac's Samples never
    /// reach the date files.
    private func delete(_ requested: DateInterval, named name: String) throws -> TrackerReply {
        guard records == true else {
            return .error(BlockLogOwner.otherMacReason)
        }
        let now = environment.clock.now
        guard requested.start < now else {
            return .error("\(TrackerReply.nothingReason) \(name)")
        }
        let range = DateInterval(start: requested.start, end: min(requested.end, now))
        let samples = try store.samples(SampleSelection(range: range))
        let edited = try editFrozenFiles(overlapping: range) { block in
            block.start < range.end && block.end > range.start ? nil : block
        }
        guard !samples.isEmpty || edited else {
            return .error("\(TrackerReply.nothingReason) \(name)")
        }
        try store.deleteRange(range, now: now, rules: rules)
        return .success
    }

    /// Applies the exclusions of the settings file as it is now to the
    /// Samples and the frozen date files of `days`.
    private func reapplyExclusions(_ days: ClosedRange<TrackingDay>) throws -> TrackerReply {
        reloadSettings()
        if let problem = monitor.problem {
            return .error("settings.toml can't be read: \(problem)")
        }
        let rules = rules
        try store.reapplyExclusions(on: days, rules: rules)
        let boundaries = try store.boundaries(rules: rules)
        let range = DateInterval(start: boundaries.start(of: days.lowerBound), end: boundaries.start(of: days.upperBound.adding(days: 1)))
        _ = try editFrozenFiles(overlapping: range, change: rules.exclusions.applied(to:))
        return .success
    }

    /// Edits the date files of the frozen dates whose blocks may overlap
    /// `range`, line by line; returns whether any file changed. A frozen
    /// file that isn't downloaded makes the request fail rather than
    /// answer as if it held nothing.
    private func editFrozenFiles(overlapping range: DateInterval, change: (ActivityBlock) -> ActivityBlock?) throws -> Bool {
        guard records == true, let cutoff = try store.meta(.cutoffDay) else {
            return false
        }
        let log = choice.log
        let boundaries = try store.boundaries(rules: rules)
        var day = boundaries.day(containing: range.start).adding(days: -1)
        var changed = false
        while day < cutoff, day <= boundaries.day(containing: range.end) {
            defer { day = day.adding(days: 1) }
            switch log.content(for: day) {
            case .missing:
                continue
            case .pendingDownload:
                throw ActivityError.fileSystem("the file of \(day) is not downloaded from iCloud Drive yet")
            case let .unreadable(reason):
                throw ActivityError.fileSystem(reason)
            case let .text(text):
                let edited = BlockLogFile.editing(text, change)
                if edited != text {
                    try log.write(text: edited, for: day)
                    changed = true
                }
            }
        }
        return changed
    }
}
