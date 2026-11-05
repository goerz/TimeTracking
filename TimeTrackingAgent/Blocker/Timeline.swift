// Timeline: one stream of samples for the user from the Mac, iPhone and
// iPad, and synced Safari history, cut into blocks (activity_tracking.md
// §2.4 to §2.7).

import Foundation
import TimeTrackingCore

/// A stretch of attention on another device: an iPhone or iPad's events
/// (§6.2) or synced Safari history (§6.1).
nonisolated struct TimelineStretch: Hashable, Sendable {
    var start: Date
    var end: Date
    var item: SampleItem
    var device: String
    /// Where stretches overlap, the higher rank wins (the later start on a tie).
    var rank: Int
}

/// Everything a day's blocks are formed from.
nonisolated struct TimelineInputs: Sendable {
    /// The Mac's samples, oldest first.
    var mac: [Sample] = []
    /// Samples reconstructed from the Mac's app usage history (§3.2).
    var reconstructed: [Sample] = []
    /// Stretches of the other devices.
    var others: [TimelineStretch] = []
    /// Times at which an iPhone or iPad Focus suspends collection.
    var closers: [Date] = []
    /// Deleted time (`delete-block`, `forget-day`): nothing there counts.
    var suppressed: [DateInterval] = []
}

/// Merges the inputs into one sample stream and runs the Blocker over it.
///
/// The Mac's attention wins: each attentive Mac sample claims the time it
/// is credited with, and another device's stretch over that time becomes a
/// background item of the Mac's time (`BackgroundWork`). Elsewhere the other devices' stretches,
/// resolved by rank, become samples every 30 seconds, and the Mac's
/// samples without attention (idle, lock, sleep) within them are dropped,
/// so a block runs on from one device to the next.
nonisolated enum Timeline {
    static let spacing: TimeInterval = 30
    /// The rank of synced Safari history, below every iOS stretch.
    static let remoteRank = 0
    /// The longest gap between two synced visits that one visit is credited across.
    static let remoteGap: TimeInterval = 300

    /// One step of the merged stream.
    enum Step: Hashable, Sendable {
        case sample(Sample, SampleOrigin)
        /// Closes the open block (a Focus that suspends collection).
        case close
    }

    /// The blocks the Blocker closed, the block still open at the end of
    /// the stream (none after a flush), and the background stretches
    /// outside the blocks, each with its background items.
    struct Result: Sendable {
        var closed: [ClosedBlock]
        var open: TrackerOpenBlock?
        var stretches: [BackgroundWork.Stretch] = []
    }

    /// The Blocker after every step before `time`, which later samples of
    /// the Mac cannot change; a later run of the same inputs plus new Mac
    /// samples continues from it.
    struct Checkpoint: Sendable {
        var time: Date
        var blocker: Blocker
        var closed: [ClosedBlock]
    }

    /// How far before the newest Mac sample a checkpoint is taken: a new
    /// sample changes only the credit of the one before it.
    static let checkpointLag: TimeInterval = 2 * Blocker.defaultCreditCap

    /// The blocks of `inputs` on the Mac `mac`; `flush` closes the block
    /// open at the end (a past day, agent shutdown, a replay). Without it,
    /// a stream that ends before `until` (now) ends with an idle sample
    /// there, so a block without attention for `idle_close` closes. With
    /// `checkpoint` (taken from the same inputs before new Mac samples were
    /// appended) only the steps from its time on run; the result carries the
    /// next checkpoint.
    static func run(
        _ inputs: TimelineInputs,
        settings: TrackerBlockSettings,
        timeZone: TimeZone,
        mac: String,
        flush: Bool,
        until: Date? = nil,
        checkpoint: Checkpoint? = nil
    ) -> (result: Result, checkpoint: Checkpoint?) {
        let merged = merged(inputs, mac: mac)
        var stream = merged.steps
        if !flush, let until {
            let marker = Sample(time: until, state: .idle)
            if let last = stream.last?.time, last < marker.time {
                stream.append(Timed(time: marker.time, order: 3, step: .sample(marker, SampleOrigin(device: mac))))
            }
        }
        var blocker = checkpoint?.blocker ?? Blocker(settings: settings, timeZone: timeZone, device: mac)
        var closed = checkpoint?.closed ?? []
        let resume = checkpoint?.time ?? .distantPast
        let next = inputs.mac.last.map { $0.time.addingTimeInterval(-checkpointLag) }
        var taken: Checkpoint?
        for timed in stream where timed.time >= resume {
            if taken == nil, let next, next > resume, timed.time >= next {
                taken = Checkpoint(time: next, blocker: blocker, closed: closed)
            }
            switch timed.step {
            case let .sample(sample, origin):
                closed += blocker.add(sample, origin: origin)
            case .close:
                closed += blocker.flush()
            }
        }
        if flush {
            closed += blocker.flush()
        }
        var blocks = ClosedBlock.resolved(closed)
        var open = flush ? nil : blocker.openSummary
        let work = BackgroundWork.assign(
            samples: merged.macSamples,
            covered: merged.covered,
            blocks: blocks.map(\.block),
            openStart: open?.start,
            frame: BackgroundWork.Frame(until: until, flush: flush, idleClose: settings.idleClose, timeZone: timeZone, mac: mac)
        )
        for index in blocks.indices {
            let items = work.blockItems[blocks[index].block.id] ?? []
            blocks[index].block.background = items
            for item in items where blocks[index].contexts[item.context] == nil {
                blocks[index].contexts[item.context] = work.contexts[item.context] ?? ""
            }
        }
        open?.background = work.openItems
        let result = Result(closed: blocks, open: open, stretches: work.stretches)
        return (result, taken ?? checkpoint)
    }

    /// Synced Safari visits (each a sample with its device) as stretches:
    /// a visit lasts until the next one when that follows within 5 minutes.
    static func remoteStretches(_ visits: [(sample: Sample, device: String)]) -> [TimelineStretch] {
        let sorted = visits.filter { $0.sample.primary != nil }.sorted { $0.sample.time < $1.sample.time }
        return zip(sorted, sorted.dropFirst()).compactMap { visit, next in
            guard let item = visit.sample.primary, next.sample.time > visit.sample.time,
                  next.sample.time.timeIntervalSince(visit.sample.time) <= remoteGap
            else {
                return nil
            }
            return TimelineStretch(start: visit.sample.time, end: next.sample.time, item: item, device: visit.device, rank: remoteRank)
        }
    }

    // MARK: Merging

    static func steps(_ inputs: TimelineInputs, mac: String) -> [Step] {
        merged(inputs, mac: mac).steps.map(\.step)
    }

    /// The merged stream, the Mac's live samples outside deleted time (for
    /// their background items), and the other devices' use during the
    /// Mac's attention.
    struct Merged: Sendable {
        var steps: [Timed]
        var macSamples: [Sample]
        var covered: [TimelineStretch]
    }

    /// The merged stream with each step's time, in order, and what
    /// `BackgroundWork` needs.
    static func merged(_ inputs: TimelineInputs, mac: String) -> Merged {
        let suppressed = inputs.suppressed
        let macSamples = (inputs.mac.map { ($0, SampleOrigin(device: mac)) }
            + inputs.reconstructed.map { ($0, SampleOrigin(device: mac, isReconstructed: true)) })
            .filter { sample, _ in !suppressed.contains { $0.start <= sample.time && sample.time < $0.end } }
            .enumerated()
            .sorted { ($0.element.0.time, $0.offset) < ($1.element.0.time, $1.offset) }
            .map(\.element)
        let coverage = claimed(by: macSamples.map(\.0))
        let others = resolve(inputs.others, cuts: inputs.closers).flatMap { stretch in
            parts(of: stretch, outside: suppressed)
        }
        let free = others.flatMap { parts(of: $0, outside: coverage) }
        let covered = others.flatMap { parts(of: $0, inside: coverage) }

        var ordered: [Timed] = []
        for closer in inputs.closers where !contains(coverage, closer) {
            ordered.append(Timed(time: closer, order: 1, step: .close))
        }
        ordered += otherSteps(free, cuts: Set(inputs.closers))
        for (sample, origin) in macSamples
            where sample.isAttentive || !free.contains(where: { $0.start <= sample.time && sample.time < $0.end })
        {
            ordered.append(Timed(time: sample.time, order: 3, step: .sample(sample, origin)))
        }
        let steps = ordered.enumerated()
            .sorted { ($0.element.time, $0.element.order, $0.offset) < ($1.element.time, $1.element.order, $1.offset) }
            .map(\.element)
        let live = macSamples.filter { !$0.1.isReconstructed }.map(\.0)
        return Merged(steps: steps, macSamples: live, covered: covered)
    }

    /// A step with its time and its order among steps of the same time:
    /// the end of a run (0), a closer (1), another device's sample (2), the Mac's (3).
    struct Timed: Sendable {
        var time: Date
        var order: Int
        var step: Step
    }

    /// The time the attentive Mac samples are credited with (up to the next
    /// sample, at most the credit cap), merged into disjoint intervals.
    static func claimed(by samples: [Sample]) -> [DateInterval] {
        var intervals: [DateInterval] = []
        for (index, sample) in samples.enumerated() where sample.isAttentive {
            let next = index + 1 < samples.count ? samples[index + 1].time : sample.time
            let length = min(Blocker.defaultCreditCap, max(0, next.timeIntervalSince(sample.time)))
            guard length > 0 else {
                continue
            }
            let interval = DateInterval(start: sample.time, duration: length)
            if let last = intervals.last, last.end >= interval.start {
                intervals[intervals.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                intervals.append(interval)
            }
        }
        return intervals
    }

    private static func contains(_ intervals: [DateInterval], _ time: Date) -> Bool {
        intervals.contains { $0.start <= time && time < $0.end }
    }

    /// The stretches cut at every boundary and at `cuts`, each piece taking
    /// the stretch of the highest rank over it (the later start on a tie);
    /// adjacent pieces of one item and device are joined unless a cut
    /// separates them.
    static func resolve(_ stretches: [TimelineStretch], cuts: [Date]) -> [TimelineStretch] {
        let sorted = stretches.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        let bounds = Set(sorted.flatMap { [$0.start, $0.end] } + cuts).sorted()
        let cutSet = Set(cuts)
        var result: [TimelineStretch] = []
        var next = 0
        var active: [TimelineStretch] = []
        for (start, end) in zip(bounds, bounds.dropFirst()) {
            while next < sorted.count, sorted[next].start <= start {
                active.append(sorted[next])
                next += 1
            }
            active.removeAll { $0.end <= start }
            guard let winner = active.max(by: { ($0.rank, $0.start) < ($1.rank, $1.start) }) else {
                continue
            }
            if var last = result.last, last.end == start, last.item == winner.item, last.device == winner.device,
               !cutSet.contains(start)
            {
                last.end = end
                result[result.count - 1] = last
            } else {
                var piece = winner
                piece.start = start
                piece.end = end
                result.append(piece)
            }
        }
        return result
    }

    /// The parts of `stretch` outside the disjoint, ordered `intervals`.
    static func parts(of stretch: TimelineStretch, outside intervals: [DateInterval]) -> [TimelineStretch] {
        var result: [TimelineStretch] = []
        var start = stretch.start
        for interval in intervals.sorted(by: { $0.start < $1.start }) where interval.end > start && interval.start < stretch.end {
            if interval.start > start {
                var piece = stretch
                piece.start = start
                piece.end = interval.start
                result.append(piece)
            }
            start = max(start, interval.end)
        }
        if start < stretch.end {
            var piece = stretch
            piece.start = start
            result.append(piece)
        }
        return result
    }

    /// The parts of `stretch` inside `intervals`.
    static func parts(of stretch: TimelineStretch, inside intervals: [DateInterval]) -> [TimelineStretch] {
        intervals.compactMap { interval in
            let start = max(stretch.start, interval.start)
            let end = min(stretch.end, interval.end)
            guard end > start else {
                return nil
            }
            var piece = stretch
            piece.start = start
            piece.end = end
            return piece
        }
    }

    /// Samples every 30 seconds within each run of adjacent pieces; at the
    /// end of a run (a gap or one of `cuts`) an attentive sample credits the
    /// last piece and an idle one stops the credit, so gaps are never counted.
    private static func otherSteps(_ pieces: [TimelineStretch], cuts: Set<Date>) -> [Timed] {
        var result: [Timed] = []
        var last: TimelineStretch?
        func sample(_ time: Date, _ state: TrackerPresenceState, _ piece: TimelineStretch) -> Step {
            .sample(
                Sample(time: time, state: state, primary: state == .idle ? nil : piece.item),
                SampleOrigin(device: piece.device)
            )
        }
        func endRun() {
            if let run = last {
                result.append(Timed(time: run.end, order: 0, step: sample(run.end, .active, run)))
                result.append(Timed(time: run.end, order: 0, step: sample(run.end, .idle, run)))
            }
            last = nil
        }
        for piece in pieces.sorted(by: { $0.start < $1.start }) {
            if let run = last, run.end != piece.start || cuts.contains(piece.start) {
                endRun()
            }
            var time = piece.start
            while time < piece.end {
                result.append(Timed(time: time, order: 2, step: sample(time, .active, piece)))
                time += spacing
            }
            last = piece
        }
        endRun()
        return result
    }
}
