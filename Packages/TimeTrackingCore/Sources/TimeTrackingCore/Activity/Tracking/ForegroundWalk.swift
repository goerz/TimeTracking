// ForegroundWalk: forming foreground blocks from the credited time and the
// endings, in time order (activity_tracking.md §2.7 step 3).

import Foundation

/// A foreground block while it forms.
struct FormingBlock: Hashable {
    var start: Date
    var credits: [Credit]
    /// The end of its credited time.
    var end: Date
    var endReason: ActivityEndReason?

    /// A block of `credits`, which are not empty.
    init(credits: [Credit]) {
        self.start = credits.first?.start ?? .distantPast
        self.credits = credits
        self.end = credits.last?.end ?? start
    }

    /// An empty block opening at `start`.
    init(start: Date) {
        self.start = start
        self.credits = []
        self.end = start
    }

    var length: TimeInterval {
        end.timeIntervalSince(start)
    }

    var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }
}

/// The walk's state machine: one open block, at most one held block, and
/// the blocks kept so far.
struct ForegroundWalk {
    private let settings: TrackerBlockSettings
    /// The Mac's device id and the times of all its Samples, to tell a
    /// stopped agent from an idle user.
    private let macDeviceID: String
    private let macSampleTimes: [Date]

    private(set) var open: FormingBlock?
    private(set) var held: (block: FormingBlock, windowEnd: Date)?
    private(set) var kept: [FormingBlock] = []

    /// How far back from the end the maximum-length cut looks for a change point.
    static let cutWindow: TimeInterval = 30 * 60

    init(settings: TrackerBlockSettings, macDeviceID: String, macSampleTimes: [Date]) {
        self.settings = settings
        self.macDeviceID = macDeviceID
        self.macSampleTimes = macSampleTimes
    }

    /// Runs the walk over `credits` and `endings` up to `horizon`.
    mutating func walk(credits: [Credit], endings: [Ending], horizon: Date) {
        var endingIndex = 0
        for credit in credits {
            while endingIndex < endings.count, endings[endingIndex].time <= credit.start {
                end(endings[endingIndex])
                endingIndex += 1
            }
            add(credit)
        }
        while endingIndex < endings.count {
            end(endings[endingIndex])
            endingIndex += 1
        }
        advance(to: horizon)
    }

    // MARK: Events

    /// Lets time pass to `time`: an open block closes after `idle_close`
    /// without credited time, and a held block whose window passed merges
    /// or is dropped.
    private mutating func advance(to time: Date) {
        while true {
            if let block = open, time >= block.end + settings.idleClose {
                open = nil
                close(block, reason: idleReason(of: block))
            } else if let held, time > held.windowEnd {
                self.held = nil
                resolve(held.block)
            } else {
                return
            }
        }
    }

    /// Credits time to the open block, reopening a held block within its
    /// window, and cuts the block where it changes work or grows too long.
    private mutating func add(_ credit: Credit) {
        advance(to: credit.start)
        if open == nil, let held {
            self.held = nil
            var reopened = held.block
            reopened.endReason = nil
            open = reopened
        }
        var piece = credit
        while true {
            var block = open ?? FormingBlock(start: piece.start)
            let limit = block.start + maxLength(of: block, adding: piece)
            if piece.end > limit, piece.start < limit {
                var first = piece
                first.end = limit
                piece.start = limit
                append(first, to: &block)
                open = block
                cutAtMaximum()
                continue
            }
            append(piece, to: &block)
            open = block
            checkSplit()
            if let current = open, current.end >= current.start + maxLength(of: current) {
                cutAtMaximum()
            }
            return
        }
    }

    /// A Sample whose state ends the block closes it at the end of its credited time.
    private mutating func end(_ ending: Ending) {
        advance(to: ending.time)
        if let block = open {
            open = nil
            close(block, reason: ending.reason)
        }
    }

    // MARK: Splits and cuts

    /// Once the block is longer than `split_after`, splits it at the change
    /// point with the largest distance while that reaches `split_threshold`.
    private mutating func checkSplit() {
        while let block = open, block.length > settings.splitAfter,
              let point = ChangePoints.best(ChangePoints.find(in: block.credits, minHalf: settings.minHalf)),
              point.distance >= settings.splitThreshold
        {
            split(block, at: point.index, reason: .split)
        }
    }

    /// Cuts the block that reached its longest length at the best change
    /// point of its last 30 minutes, or closes it there without one.
    private mutating func cutAtMaximum() {
        guard let block = open else {
            return
        }
        let recent = ChangePoints.find(in: block.credits, minHalf: settings.minHalf)
            .filter { $0.time >= block.end - Self.cutWindow }
        if let point = ChangePoints.best(recent) {
            split(block, at: point.index, reason: .maxLength)
        } else {
            open = nil
            close(block, reason: .maxLength)
        }
    }

    /// Closes the part before `index` with `reason`; the rest stays open.
    private mutating func split(_ block: FormingBlock, at index: Int, reason: ActivityEndReason) {
        open = FormingBlock(credits: Array(block.credits[index...]))
        close(FormingBlock(credits: Array(block.credits[..<index])), reason: reason)
    }

    private func maxLength(of block: FormingBlock, adding credit: Credit? = nil) -> TimeInterval {
        let credits = block.credits + (credit.map { [$0] } ?? [])
        let total = credits.reduce(0) { $0 + $1.seconds }
        let passive = credits.filter(\.isPassive).reduce(0) { $0 + $1.seconds }
        return passive * 2 > total ? settings.maxPassiveBlock : settings.maxBlock
    }

    private mutating func append(_ credit: Credit, to block: inout FormingBlock) {
        guard credit.end > credit.start else {
            return
        }
        block.credits.append(credit)
        block.end = max(block.end, credit.end)
    }

    // MARK: Closing

    /// `stopped` when the last credited Sample was the Mac's and the Mac
    /// took no Sample at all until the block closed, else `idle`.
    private func idleReason(of block: FormingBlock) -> ActivityEndReason {
        guard let last = block.credits.last, last.deviceID == macDeviceID else {
            return .idle
        }
        let closeTime = block.end + settings.idleClose
        let tookSample = macSampleTimes.contains { $0 > last.sampleTime && $0 <= closeTime }
        return tookSample ? .idle : .stopped
    }

    /// Keeps a closed block, holds a short one, drops one without credited
    /// time. A block held before (possible only when `min_half` is shorter
    /// than `min_block`) is resolved first.
    private mutating func close(_ block: FormingBlock, reason: ActivityEndReason) {
        guard !block.credits.isEmpty else {
            return
        }
        if let held {
            self.held = nil
            resolve(held.block)
        }
        var closed = block
        closed.endReason = reason
        if closed.length < settings.minBlock {
            held = (closed, closed.end + settings.idleClose + closed.length)
        } else {
            kept.append(closed)
        }
    }

    /// A held block whose window passed merges into the previous block when
    /// the gap fits in the window and the merged block in `max_block`;
    /// otherwise it is dropped.
    private mutating func resolve(_ block: FormingBlock) {
        guard var previous = kept.last else {
            return
        }
        let window = settings.idleClose + block.length
        guard block.start.timeIntervalSince(previous.end) <= window, block.end.timeIntervalSince(previous.start) <= settings.maxBlock else {
            return
        }
        previous.credits += block.credits
        previous.end = block.end
        previous.endReason = block.endReason
        kept[kept.count - 1] = previous
    }
}
