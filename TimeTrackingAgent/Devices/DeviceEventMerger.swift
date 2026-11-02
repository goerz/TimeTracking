// DeviceEventMerger: one device-day's DeviceEvents as blocks with `src`
// `device` (spec_activity_tracking.md §6.2, §7.2; spec_ios.md §9).

import Foundation
import TimeTrackingCore

/// Turns the events of one device on one local day into closed blocks.
///
/// Each event becomes a stretch of attention with an item and a rank:
/// - a counted ladder step k (not `early`) covers the minutes since the
///   set's previous counted step, ending at its time (one minute for the
///   day's first), with the set's label as context, subject, and group key;
/// - a web extension tab covers up to a minute, until the next tab, as a
///   `safari` item under the browser rules of §3.3 and the exclusions;
/// - an `appOpened` automation covers the time to the matching
///   `appClosed` (at most `max_block`), any other automation a minute,
///   with its label;
/// - the app's `foreground` covers the time to its `background`.
/// Where stretches overlap the most specific wins: the app, then
/// automations, web tabs, named sets, and "Everything" last. A Focus that
/// suspends collection closes the block at its `on`. The stretches become
/// samples every 30 seconds for the Blocker, so gaps over `idle_close`,
/// the split test, midnight, and the summary rules apply as on the Mac.
nonisolated struct DeviceEventMerger {
    /// The sample spacing within a stretch.
    static let spacing: TimeInterval = 30
    /// What a point event covers.
    static let pointLength: TimeInterval = 60
    static let safariApp = "com.apple.mobilesafari"

    var settings: TrackerSettings
    var exclusions: ExclusionRules

    /// A stretch of attention.
    struct Stretch {
        var start: Date
        var end: Date
        var item: SampleItem
        var rank: Int
    }

    func blocks(_ events: [DeviceEvent], device: String, timeZone: TimeZone) -> [ClosedBlock] {
        let sorted = events.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }
        guard let first = sorted.first else {
            return []
        }
        let dayStart = ActivityTimestamp.startOfDay(first.time, timeZone: timeZone)
        let dayEnd = ActivityTimestamp.nextMidnight(after: first.time, timeZone: timeZone)
        let stretches = (ladder(sorted, dayStart: dayStart) + web(sorted) + intents(sorted) + app(sorted)).compactMap { stretch in
            var clipped = stretch
            clipped.start = max(stretch.start, dayStart)
            clipped.end = min(stretch.end, dayEnd)
            return clipped.end > clipped.start ? clipped : nil
        }
        let closers = sorted.filter { $0.source == .focus && $0.kind == "on" && !$0.payloadBool("collect", default: true) }.map(\.time)
        var blocker = Blocker(settings: settings.blocks, timeZone: timeZone, device: device, source: .device)
        var closed: [ClosedBlock] = []
        for step in steps(segments(stretches, cuts: closers), closers: closers) {
            switch step {
            case let .sample(sample):
                closed += blocker.add(sample)
            case .close:
                closed += blocker.flush()
            }
        }
        return ClosedBlock.resolved(closed + blocker.flush())
    }

    // MARK: Stretches

    private func ladder(_ events: [DeviceEvent], dayStart: Date) -> [Stretch] {
        var previous: [String: (step: Int, time: Date)] = [:]
        var result: [Stretch] = []
        for event in events where event.source == .ladder && event.kind == "minute" && !event.payloadBool("early", default: false) {
            guard let step = event.payloadInt("n") else {
                continue
            }
            let last = previous[event.label]
            if let last, step <= last.step {
                continue
            }
            let minutes = last.map { step - $0.step } ?? 1
            let start = max(last?.time ?? dayStart, event.time.addingTimeInterval(-TimeInterval(minutes) * 60))
            previous[event.label] = (step, event.time)
            let everything = event.label == LadderSet.everythingLabel
            let item = SampleItem(context: event.label, subject: event.label, groupKey: event.label, app: "ladder")
            result.append(Stretch(start: start, end: event.time, item: item, rank: everything ? 1 : 3))
        }
        return result
    }

    private func web(_ events: [DeviceEvent]) -> [Stretch] {
        let tabs = events.filter { $0.source == .webext && $0.kind == "tab" }
        let rules = BrowserItemRules(settings: settings.browser, exclusions: exclusions)
        return tabs.enumerated().compactMap { index, event in
            guard let parts = rules.parts(for: "https://" + event.label) else {
                return nil
            }
            let item = SampleItem(browser: "safari", parts: parts, app: Self.safariApp)
            var end = event.time.addingTimeInterval(Self.pointLength)
            if index + 1 < tabs.count {
                end = min(end, tabs[index + 1].time)
            }
            return Stretch(start: event.time, end: end, item: item, rank: 4)
        }
    }

    private func intents(_ events: [DeviceEvent]) -> [Stretch] {
        let automations = events.filter { $0.source == .intent }
        var result: [Stretch] = []
        let opened = ActivityEventKind.appOpened.rawValue
        let closed = ActivityEventKind.appClosed.rawValue
        for (index, event) in automations.enumerated() where event.kind != closed {
            var end = event.time.addingTimeInterval(Self.pointLength)
            let next = automations[(index + 1)...].first { $0.label == event.label && ($0.kind == opened || $0.kind == closed) }
            if event.kind == opened, let next, next.kind == closed, next.time.timeIntervalSince(event.time) <= settings.blocks.maxBlock {
                end = next.time
            }
            let item = SampleItem(context: event.label, subject: event.label, groupKey: event.label, app: "intent")
            result.append(Stretch(start: event.time, end: end, item: item, rank: 5))
        }
        return result
    }

    private func app(_ events: [DeviceEvent]) -> [Stretch] {
        let transitions = events.filter { $0.source == .app }
        var result: [Stretch] = []
        for (index, event) in transitions.enumerated() where event.kind == "foreground" {
            var end = event.time.addingTimeInterval(Self.pointLength)
            if let next = transitions[(index + 1)...].first, next.time.timeIntervalSince(event.time) <= settings.blocks.maxBlock {
                end = next.time
            }
            let item = SampleItem(
                context: CollectionLog.appLabel,
                subject: CollectionLog.appLabel,
                groupKey: CollectionLog.appLabel,
                app: "app"
            )
            result.append(Stretch(start: event.time, end: end, item: item, rank: 6))
        }
        return result
    }

    // MARK: Segments and samples

    /// The stretches cut at every boundary and at `cuts`, each piece taking
    /// the item of the highest-ranked stretch over it (the later start on a
    /// tie); adjacent pieces of one item are joined unless a cut separates them.
    private func segments(_ stretches: [Stretch], cuts: [Date]) -> [Stretch] {
        let bounds = Set(stretches.flatMap { [$0.start, $0.end] } + cuts).sorted()
        var result: [Stretch] = []
        for (start, end) in zip(bounds, bounds.dropFirst()) {
            let covering = stretches.filter { $0.start <= start && $0.end >= end }
            guard let winner = covering.max(by: { ($0.rank, $0.start) < ($1.rank, $1.start) }) else {
                continue
            }
            if var last = result.last, last.end == start, last.item == winner.item, !cuts.contains(start) {
                last.end = end
                result[result.count - 1] = last
            } else {
                result.append(Stretch(start: start, end: end, item: winner.item, rank: winner.rank))
            }
        }
        return result
    }

    /// What the Blocker is fed: a sample, or the end of the open block.
    enum Step {
        case sample(Sample)
        case close
    }

    /// Samples every 30 seconds within each segment; at the end of a run an
    /// attentive sample credits the last stretch and an idle one stops the
    /// credit, so gaps are never counted. A cut closes the block there.
    private func steps(_ segments: [Stretch], closers: [Date]) -> [Step] {
        var result: [Step] = []
        var open: Stretch?
        var pendingClosers = closers.sorted()
        func endRun() {
            if let run = open {
                result.append(.sample(Sample(time: run.end, state: .active, primary: run.item)))
                result.append(.sample(Sample(time: run.end, state: .idle)))
            }
            open = nil
        }
        func close(upTo time: Date) {
            while let closer = pendingClosers.first, closer <= time {
                pendingClosers.removeFirst()
                endRun()
                result.append(.close)
            }
        }
        for segment in segments {
            close(upTo: segment.start)
            if let run = open, run.end != segment.start {
                endRun()
            }
            var time = segment.start
            while time < segment.end {
                result.append(.sample(Sample(time: time, state: .active, primary: segment.item)))
                time += Self.spacing
            }
            open = segment
        }
        endRun()
        return result
    }
}
