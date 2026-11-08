// BackgroundBlocks: background work between foreground blocks
// (activity_tracking.md §2.7 step 3).

import Foundation

/// A background block while it forms.
struct FormingBackgroundBlock: Hashable {
    var start: Date
    var end: Date
    var pieces: [BackgroundPiece]
    var endReason: ActivityEndReason?
}

enum BackgroundBlocks {
    /// The background blocks of the pieces outside every foreground range:
    /// a block ends after `idle_close` without a piece (`idle`), at the next
    /// foreground block (`split`), or at `max_background_block`
    /// (`maxLength`). The block left open at `horizon` has no end reason.
    static func form(
        _ pieces: [BackgroundPiece],
        outside foreground: [DateInterval],
        horizon: Date,
        settings: TrackerBlockSettings
    ) -> [FormingBackgroundBlock] {
        let outside = pieces.flatMap { subtracting(foreground, from: $0) }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        let foregroundStarts = foreground.map(\.start).sorted()
        var blocks: [FormingBackgroundBlock] = []
        var open: FormingBackgroundBlock?

        func closeIfDue(before time: Date) {
            guard let block = open else {
                return
            }
            let idleAt = block.end + settings.idleClose
            if let next = foregroundStarts.first(where: { $0 >= block.end }), next <= min(time, idleAt) {
                blocks.append(closed(block, .split))
                open = nil
            } else if time >= idleAt {
                blocks.append(closed(block, .idle))
                open = nil
            }
        }

        for var piece in outside {
            closeIfDue(before: piece.start)
            while true {
                var block = open ?? FormingBackgroundBlock(start: piece.start, end: piece.start, pieces: [])
                let limit = block.start + settings.maxBackgroundBlock
                if piece.end > limit, piece.start < limit {
                    var first = piece
                    first.end = limit
                    piece.start = limit
                    block.pieces.append(first)
                    block.end = limit
                    blocks.append(closed(block, .maxLength))
                    open = nil
                    continue
                }
                if piece.start >= limit {
                    blocks.append(closed(block, .maxLength))
                    open = nil
                    continue
                }
                block.pieces.append(piece)
                block.end = max(block.end, piece.end)
                open = block
                break
            }
        }
        closeIfDue(before: horizon)
        if let open {
            blocks.append(open)
        }
        return blocks.compactMap { keepingLongItems($0, settings: settings) }
    }

    private static func closed(_ block: FormingBackgroundBlock, _ reason: ActivityEndReason) -> FormingBackgroundBlock {
        var result = block
        result.endReason = reason
        return result
    }

    /// A closed block without its items under `min_background_item`,
    /// trimmed to the pieces it keeps, `nil` when none is left; an open
    /// block as it is, since its items may still grow.
    private static func keepingLongItems(_ block: FormingBackgroundBlock, settings: TrackerBlockSettings) -> FormingBackgroundBlock? {
        guard block.endReason != nil else {
            return block
        }
        var seconds: [PieceKey: TimeInterval] = [:]
        for piece in block.pieces {
            seconds[PieceKey(piece), default: 0] += piece.end.timeIntervalSince(piece.start)
        }
        var result = block
        result.pieces = block.pieces.filter { (seconds[PieceKey($0)] ?? 0) >= settings.minBackgroundItem }
        guard let start = result.pieces.map(\.start).min(), let end = result.pieces.map(\.end).max() else {
            return nil
        }
        result.start = start
        result.end = end
        return result
    }

    /// An Item on a device.
    private struct PieceKey: Hashable {
        var deviceID: String
        var item: ActivityItem

        init(_ piece: BackgroundPiece) {
            self.deviceID = piece.deviceID
            self.item = piece.item
        }
    }

    /// The parts of `piece` outside every interval.
    static func subtracting(_ intervals: [DateInterval], from piece: BackgroundPiece) -> [BackgroundPiece] {
        var parts = [piece]
        for interval in intervals where interval.start < piece.end && interval.end > piece.start {
            parts = parts.flatMap { part -> [BackgroundPiece] in
                guard interval.start < part.end, interval.end > part.start else {
                    return [part]
                }
                var result: [BackgroundPiece] = []
                if part.start < interval.start {
                    var before = part
                    before.end = interval.start
                    result.append(before)
                }
                if part.end > interval.end {
                    var after = part
                    after.start = interval.end
                    result.append(after)
                }
                return result
            }
        }
        return parts
    }
}
