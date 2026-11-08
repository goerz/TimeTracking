// BlockFormer: one pass of the rebuild loop, the blocks that start on one
// date formed from the Samples alone (activity_tracking.md §2.7).

public import Foundation

/// What a pass found for its date.
public struct DatePass: Sendable, Hashable {
    /// The date's closed blocks, foreground and background, by start.
    public var blocks: [ActivityBlock]
    /// Where the date's last block ends, or that it is unsettled.
    public var end: DateEnd
    /// What the pass means for the block of `current.json`.
    public var current: CurrentBlockUpdate
}

/// The effect of a pass on the open block of `current.json` (§2.7 step 4).
public enum CurrentBlockUpdate: Sendable, Hashable {
    /// The walk stopped at the end of its read range: the block stays as it is.
    case unchanged
    /// The walk reached now: the foreground block it left open, or `nil`.
    case set(ActivityBlock?)
}

/// Forms the blocks of one date: covers and competes the Samples, walks the
/// credited time into foreground blocks, forms background blocks between
/// them, and keeps the blocks that start before the next date's 00:00.
public struct BlockFormer: Sendable {
    let settings: TrackerBlockSettings
    /// This Mac's device id, whose silence tells a stopped agent.
    let macDeviceID: String
    /// The current name of each device id.
    let deviceNames: [String: String]

    public init(settings: TrackerBlockSettings, macDeviceID: String, deviceNames: [String: String]) {
        self.settings = settings
        self.macDeviceID = macDeviceID
        self.deviceNames = deviceNames
    }

    /// Where a pass of `day` stops reading: the next date's 00:00 plus `max_passive_block`.
    public func readEnd(of day: TrackingDay, boundaries: DayBoundaries) -> Date {
        boundaries.start(of: day.adding(days: 1)) + settings.maxPassiveBlock
    }

    /// The pass of `day` over `samples` (by time, from `readStart` through
    /// the read end), walking up to `now` at the latest.
    public func pass(day: TrackingDay, samples: [Sample], boundaries: DayBoundaries, readStart: Date, now: Date) -> DatePass {
        let nextStart = boundaries.start(of: day.adding(days: 1))
        let readEnd = readEnd(of: day, boundaries: boundaries)
        let horizon = max(readStart, min(readEnd, now))
        let claims = claims(of: samples, readStart: readStart, horizon: horizon)
        var walk = ForegroundWalk(
            settings: settings,
            macDeviceID: macDeviceID,
            macSampleTimes: samples.filter { $0.deviceID == macDeviceID }.map(\.time)
        )
        walk.walk(credits: claims.credits, endings: claims.endings, horizon: horizon)
        // A held block may still be dropped, so only kept and open blocks end background blocks.
        let foregroundRanges = (walk.kept + [walk.open].compactMap(\.self)).map(\.interval)
        let background = BackgroundBlocks.form(claims.background, outside: foregroundRanges, horizon: horizon, settings: settings)

        let offset = boundaries.offset(of: day)
        let keptOnDay = walk.kept.filter { $0.start < nextStart }
        let backgroundOnDay = background.filter { $0.endReason != nil && $0.start < nextStart }
        var blocks = keptOnDay.map { foregroundBlock($0, background: claims.background, offset: offset) }
        blocks += backgroundOnDay.map { backgroundBlock($0, offset: offset) }
        blocks.sort { $0.start < $1.start }
        let lastEnd = blocks.map(\.end).max()

        let settled = horizon >= readEnd || isSettled(
            walk: walk,
            openBackground: background.filter { $0.endReason == nil },
            nextStart: nextStart,
            lastEnd: lastEnd,
            horizon: horizon
        )
        return DatePass(
            blocks: blocks,
            end: settled ? .settled(lastEnd) : .unsettled,
            current: horizon < readEnd ? .set(walk.open.map { openBlock($0, background: claims.background, offset: offset) }) : .unchanged
        )
    }

    /// Whether the walk would stop by `horizon`: at a block after midnight
    /// that can no longer merge, or once nothing is open or held and
    /// `idle_close` plus `min_block` have passed since the date's last block.
    private func isSettled(
        walk: ForegroundWalk,
        openBackground: [FormingBackgroundBlock],
        nextStart: Date,
        lastEnd: Date?,
        horizon: Date
    ) -> Bool {
        let blockAfterMidnight = walk.kept.contains { $0.start >= nextStart }
            || walk.open.map { $0.start >= nextStart && $0.length >= settings.minBlock } ?? false
        if blockAfterMidnight {
            return true
        }
        if walk.open != nil || walk.held != nil || openBackground.contains(where: { $0.start < nextStart }) {
            return false
        }
        let stop = max(nextStart, lastEnd.map { $0 + settings.idleClose + settings.minBlock } ?? nextStart)
        return horizon >= stop
    }

    // MARK: Assembly

    private func foregroundBlock(_ block: FormingBlock, background: [BackgroundPiece], offset: Int) -> ActivityBlock {
        ActivityBlock(
            start: block.start,
            end: block.end,
            utcOffset: offset,
            endReason: block.endReason,
            reconstructedSeconds: block.credits.filter(\.isReconstructed).reduce(0) { $0 + $1.seconds },
            foreground: items(block.credits.map { ItemPart(deviceID: $0.deviceID, item: $0.item, seconds: $0.seconds) }),
            background: backgroundItems(background, within: block.interval)
        )
    }

    private func openBlock(_ block: FormingBlock, background: [BackgroundPiece], offset: Int) -> ActivityBlock {
        var open = foregroundBlock(block, background: background, offset: offset)
        open.endReason = nil
        open.isOpen = true
        return open
    }

    private func backgroundBlock(_ block: FormingBackgroundBlock, offset: Int) -> ActivityBlock {
        ActivityBlock(
            start: block.start,
            end: block.end,
            utcOffset: offset,
            endReason: block.endReason,
            background: items(block.pieces.map { piece in
                ItemPart(deviceID: piece.deviceID, item: piece.item, seconds: Int(piece.end.timeIntervalSince(piece.start)))
            })
        )
    }

    /// The background pieces inside `interval`, clipped to it.
    private func backgroundItems(_ pieces: [BackgroundPiece], within interval: DateInterval) -> [ActivityBlockItem] {
        items(pieces.compactMap { piece in
            let start = max(piece.start, interval.start)
            let end = min(piece.end, interval.end)
            return end > start ? ItemPart(deviceID: piece.deviceID, item: piece.item, seconds: Int(end.timeIntervalSince(start))) : nil
        })
    }

    /// One device's seconds on an Item, before the merge into BlockItems.
    private struct ItemPart {
        let deviceID: String
        let item: ActivityItem
        let seconds: Int
    }

    /// The parts as BlockItems, each named by its device's current name,
    /// equal Items on one device added up (§2.2).
    private func items(_ parts: [ItemPart]) -> [ActivityBlockItem] {
        ActivityBlockItem.merged(parts.map { part in
            ActivityBlockItem(device: deviceNames[part.deviceID] ?? part.deviceID, seconds: part.seconds, item: part.item)
        })
    }
}
