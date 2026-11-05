// Blocker: forming blocks from samples (activity_tracking.md §2.5).

import Foundation
import TimeTrackingCore

/// Turns a time-ordered stream of samples into closed blocks.
///
/// Each attentive sample is credited with the time up to the next sample
/// (at most `creditCap`), so the last sample before a gap gets nothing and
/// a block ends at its last attentive sample; idle gaps shorter than
/// `idle_close` are absorbed without counting. A block closes after
/// `idle_close` without attention, on lock, sleep, display sleep, or a
/// user switch (at the event time), at local midnight, by the split test,
/// and on reaching `max_block` (`max_passive_block` when mostly passive).
///
/// A block that closes shorter than `min_block` is held back. Attention
/// within its merge window (`idle_close` plus its own length) after its end
/// reopens it, so it continues into the next block; otherwise it merges into
/// the previous block of the same stream when that ended within the window
/// before it (a `ClosedBlock` that replaces the previous one), or is dropped.
/// Neither crosses midnight, a `flush`, or `max_block`.
///
/// Each sample comes with its origin, the device it was observed on and
/// whether it was reconstructed (§2.4); a block sums its time per device.
/// Background items are not the Blocker's: `BackgroundWork` assigns their
/// time to blocks and background stretches (§2.7).
nonisolated struct Blocker: Sendable {
    /// The most one sample is credited with, so a missed tick cannot inflate `a`.
    static let defaultCreditCap: TimeInterval = 60
    /// How far back `max_block` looks for a change point.
    static let maxBlockLookback: TimeInterval = 1800

    var settings: TrackerBlockSettings
    let timeZone: TimeZone
    /// The recording Mac, the origin of a sample added without one.
    let device: String
    private(set) var open: OpenBlock?
    /// A closed block shorter than `min_block`, waiting for a neighbor.
    var held: RawBlock?
    /// The last block handed out, for a backward merge.
    var previous: RawBlock?

    init(settings: TrackerBlockSettings, timeZone: TimeZone, device: String) {
        self.settings = settings
        self.timeZone = timeZone
        self.device = device
    }

    /// A credited stretch of one item on one device.
    struct Segment: Hashable, Sendable {
        var start: Date
        var seconds: Int
        var item: SampleItem
        var passive: Bool
        var device: String
        var isReconstructed = false
    }

    /// The last attentive sample, credited when the next sample arrives.
    struct Pending: Hashable, Sendable {
        var time: Date
        var item: SampleItem
        var passive: Bool
        var origin: SampleOrigin
    }

    /// The open block.
    struct OpenBlock: Hashable, Sendable {
        var start: Date
        var segments: [Segment] = []
        var pending: Pending?
        var lastAttentive: Date
        var contexts: [String: String] = [:]
    }

    // MARK: Samples

    /// Adds `sample` of the recording Mac (not earlier than the previous
    /// one) and returns the blocks it closed, oldest first.
    mutating func add(_ sample: Sample) -> [ClosedBlock] {
        add(sample, origin: SampleOrigin(device: device))
    }

    /// Adds `sample` observed at `origin` and returns the blocks it closed,
    /// oldest first.
    mutating func add(_ sample: Sample, origin: SampleOrigin) -> [ClosedBlock] {
        var closed: [ClosedBlock] = []
        let time = sample.time
        if let block = open, ActivityTimestamp.startOfDay(time, timeZone: timeZone) > ActivityTimestamp.startOfDay(
            block.start,
            timeZone: timeZone
        ) {
            let midnight = ActivityTimestamp.nextMidnight(after: block.start, timeZone: timeZone)
            if sample.isAttentive, time.timeIntervalSince(block.lastAttentive) < settings.idleClose {
                credit(until: min(midnight, time))
                closed += close(end: midnight)
            } else {
                closed += close(end: block.lastAttentive)
            }
        }
        // After the midnight close, so a block held at midnight settles here.
        if let short = held, !canContinue(short, at: time) {
            closed += resolveHeld()
        }
        if let event = sample.event, event.closesBlock {
            if open != nil {
                credit(until: time)
                closed += close(end: time)
            }
            return closed
        }
        if let block = open, time.timeIntervalSince(block.lastAttentive) >= settings.idleClose {
            closed += close(end: block.lastAttentive)
        }
        guard sample.isAttentive, let item = sample.primary else {
            // An absorbed gap: the last attentive sample before it is not credited.
            open?.pending = nil
            return closed
        }
        if open == nil, let short = held, canContinue(short, at: time) {
            // Attention within the merge window: the short block continues,
            // and the gap is absorbed without counting.
            held = nil
            open = OpenBlock(
                start: short.start,
                segments: short.segments,
                lastAttentive: time,
                contexts: short.contexts
            )
        } else if open == nil {
            closed += resolveHeld()
            open = OpenBlock(start: time, lastAttentive: time)
        } else {
            credit(until: time)
        }
        open?.pending = Pending(time: time, item: item, passive: sample.state == .passive, origin: origin)
        open?.lastAttentive = time
        if open?.contexts[item.context] == nil {
            open?.contexts[item.context] = item.app
        }
        closed += checkLength(now: time)
        return closed
    }

    /// Closes the open block at its last attentive sample and settles a
    /// held short block (end of a replay or a batch, agent shutdown); no
    /// later block merges across it.
    mutating func flush() -> [ClosedBlock] {
        var closed: [ClosedBlock] = []
        if let block = open {
            closed += close(end: block.lastAttentive)
        }
        closed += resolveHeld()
        previous = nil
        return closed
    }

    /// The open block as `current.json` shows it, or `nil`.
    var openSummary: TrackerOpenBlock? {
        guard let block = open else {
            return nil
        }
        let summary = BlockSummary(segments: block.segments, settings: settings, mac: device)
        return TrackerOpenBlock(
            start: block.start,
            activeSeconds: summary.activeSeconds,
            devices: summary.devices,
            groupKey: summary.groupKey,
            groupShare: summary.groupShare,
            items: summary.items,
            background: [],
            reconstructedSeconds: summary.reconstructedSeconds
        )
    }

    // MARK: Crediting and closing

    /// Credits the pending sample with the time up to `time`, capped.
    private mutating func credit(until time: Date) {
        guard let pending = open?.pending else {
            return
        }
        let seconds = Int(min(Self.defaultCreditCap, max(0, time.timeIntervalSince(pending.time))))
        open?.pending = nil
        guard seconds > 0 else {
            return
        }
        open?.segments.append(Segment(
            start: pending.time,
            seconds: seconds,
            item: pending.item,
            passive: pending.passive,
            device: pending.origin.device,
            isReconstructed: pending.origin.isReconstructed
        ))
    }

    /// Closes the whole open block at `end`; a block shorter than
    /// `min_block` is held back.
    private mutating func close(end: Date) -> [ClosedBlock] {
        guard let block = open else {
            return []
        }
        open = nil
        let raw = RawBlock(
            start: block.start,
            end: max(block.start, end),
            segments: block.segments,
            contexts: block.contexts
        )
        guard raw.length < settings.minBlock else {
            return emit(raw)
        }
        if raw.segments.contains(where: { $0.seconds > 0 }) {
            held = raw
        }
        return []
    }

    func finish(_ raw: RawBlock, replacesPrevious: Bool = false) -> [ClosedBlock] {
        let (start, end, contexts) = (raw.start, raw.end, raw.contexts)
        let summary = BlockSummary(segments: raw.segments, settings: settings, mac: device)
        guard summary.activeSeconds > 0 else {
            return []
        }
        let used = Set(summary.detailItems.map(\.context))
        let block = ActivityBlock(
            start: start,
            end: end,
            activeSeconds: summary.activeSeconds,
            devices: summary.devices,
            groupKey: summary.groupKey,
            groupShare: summary.groupShare,
            items: summary.items,
            utcOffset: timeZone.secondsFromGMT(for: start),
            reconstructedSeconds: summary.reconstructedSeconds
        )
        let closed = ClosedBlock(
            block: block,
            detailItems: summary.detailItems,
            contexts: contexts.filter { used.contains($0.key) },
            replacesPrevious: replacesPrevious
        )
        return [closed]
    }

    // MARK: Split test and max_block

    /// Runs the split test and the `max_block` rule after a sample at `now`.
    private mutating func checkLength(now: Date) -> [ClosedBlock] {
        var closed: [ClosedBlock] = []
        while let block = open {
            let length = now.timeIntervalSince(block.start)
            if length > settings.splitAfter, let best = SplitTest.best(
                in: block.segments,
                minHalf: settings.minHalf
            ), best.distance >= settings.splitThreshold {
                closed += split(at: best.index)
                continue
            }
            guard length >= lengthLimit(block.segments) else {
                break
            }
            if let best = SplitTest.best(in: block.segments, minHalf: 0, after: now.addingTimeInterval(-Self.maxBlockLookback)) {
                closed += split(at: best.index)
                continue
            }
            closed += emit(RawBlock(
                start: block.start,
                end: now,
                segments: block.segments,
                contexts: block.contexts
            ))
            open = OpenBlock(start: now, pending: block.pending, lastAttentive: block.lastAttentive, contexts: block.contexts)
            break
        }
        return closed
    }

    /// Closes the segments before `index` as a block ending where segment
    /// `index` starts; the rest stays open.
    private mutating func split(at index: Int) -> [ClosedBlock] {
        guard let block = open, index > 0, index < block.segments.count else {
            return []
        }
        let point = block.segments[index].start
        let closed = emit(RawBlock(
            start: block.start,
            end: point,
            segments: Array(block.segments[..<index]),
            contexts: block.contexts
        ))
        var rest = block
        rest.start = point
        rest.segments = Array(block.segments[index...])
        open = rest
        return closed
    }
}
