// BlockFormer+Competition: what each Sample covers, which Sample wins the
// foreground where several claim the same time, and which states end a
// block (activity_tracking.md §2.7 steps 2 and 3).

import Foundation

/// Time a winning Sample credits to its device and foreground Item.
struct Credit: Hashable {
    var start: Date
    var end: Date
    var deviceID: String
    var item: ActivityItem
    var isPassive: Bool
    var isReconstructed: Bool
    /// The time of the Sample that earned it.
    var sampleTime: Date

    var seconds: Int {
        Int(end.timeIntervalSince(start))
    }
}

/// Time a background Item earns on its device.
struct BackgroundPiece: Hashable {
    var start: Date
    var end: Date
    var deviceID: String
    var item: ActivityItem
}

/// A Sample whose state ends the open block.
struct Ending: Hashable {
    var time: Date
    var reason: ActivityEndReason
}

extension BlockFormer {
    /// What the Samples of a pass give the walk.
    struct Claims {
        var credits: [Credit] = []
        var background: [BackgroundPiece] = []
        var endings: [Ending] = []
    }

    /// Covers, competes, and finds the endings of `samples` (sorted by time)
    /// within `[readStart, horizon)`.
    func claims(of samples: [Sample], readStart: Date, horizon: Date) -> Claims {
        let covers = Self.coverage(of: samples, horizon: horizon)
        var claims = Claims()
        claims.endings = endings(of: samples, covers: covers, readStart: readStart, horizon: horizon)
        var claimants: [Claimant] = []
        for (index, sample) in samples.enumerated() {
            let start = max(sample.time, readStart)
            let end = min(covers[index], horizon)
            guard end > start else {
                continue
            }
            for item in sample.background {
                claims.background.append(BackgroundPiece(start: start, end: end, deviceID: sample.deviceID, item: item))
            }
            if sample.isAttentive, let item = sample.foreground {
                claimants.append(Claimant(sample: sample, item: item, start: start, end: end))
            }
        }
        compete(claimants, into: &claims)
        claims.credits = Self.coalesced(claims.credits)
        return claims
    }

    /// The end of the time each Sample covers: the next Sample of its
    /// series (`Sample.series`), at most 60 seconds on, never past `horizon`.
    static func coverage(of samples: [Sample], horizon: Date) -> [Date] {
        var next: [String: Date] = [:]
        var result = Array(repeating: Date.distantPast, count: samples.count)
        for (index, sample) in samples.enumerated().reversed() {
            let key = sample.series
            let limit = sample.time + Sample.maxCoverage
            result[index] = min(next[key].map { min($0, limit) } ?? limit, max(horizon, sample.time))
            next[key] = sample.time
        }
        return result
    }

    /// The Samples whose state ends the open block: `locked`, `asleep`,
    /// `otherUser`, or `paused`, unless an attentive Sample covers their
    /// time (any device's, such as the device's own Screen Time) or an
    /// attentive Sample of another device follows within `idle_close`;
    /// then they count as `idle`.
    private func endings(of samples: [Sample], covers: [Date], readStart: Date, horizon: Date) -> [Ending] {
        let attentive = samples.indices.filter { samples[$0].isAttentive }
        return samples.indices.compactMap { index in
            let sample = samples[index]
            guard let reason = sample.state.endReason, sample.time >= readStart, sample.time < horizon else {
                return nil
            }
            let excused = attentive.contains { other in
                let claim = samples[other]
                let covering = claim.time <= sample.time && covers[other] > sample.time
                let following = claim.deviceID != sample.deviceID && claim.time >= sample.time
                    && claim.time <= sample.time + settings.idleClose
                return covering || following
            }
            return excused ? nil : Ending(time: sample.time, reason: reason)
        }
    }

    /// An attentive Sample's claim on its covered time.
    private struct Claimant {
        var sample: Sample
        var item: ActivityItem
        var start: Date
        var end: Date
    }

    /// Splits the claimed time into slices; in each the best-ranked claim
    /// wins (the later Sample on a tie) and credits its Item. A losing
    /// claim of another device becomes a background Item on its device; one
    /// of the winner's device credits nothing.
    private func compete(_ claimants: [Claimant], into claims: inout Claims) {
        let cuts = Set(claimants.flatMap { [$0.start, $0.end] }).sorted()
        var active: [Claimant] = []
        var waiting = claimants.sorted { $0.start < $1.start }[...]
        for (start, end) in zip(cuts, cuts.dropFirst()) {
            active.removeAll { $0.end <= start }
            while let next = waiting.first, next.start <= start {
                active.append(next)
                waiting = waiting.dropFirst()
            }
            let present = active.filter { $0.start <= start && $0.end >= end }
            guard let winner = present.min(by: Self.outranks) else {
                continue
            }
            claims.credits.append(Credit(
                start: start,
                end: end,
                deviceID: winner.sample.deviceID,
                item: winner.item,
                isPassive: winner.sample.state == .passive,
                isReconstructed: winner.sample.source == .appUsage,
                sampleTime: winner.sample.time
            ))
            for loser in present where loser.sample.deviceID != winner.sample.deviceID {
                claims.background.append(BackgroundPiece(start: start, end: end, deviceID: loser.sample.deviceID, item: loser.item))
            }
        }
    }

    /// Whether `lhs` wins over `rhs`: a better rank, else the later Sample,
    /// else the smaller device id, so every pass picks alike.
    private static func outranks(_ lhs: Claimant, _ rhs: Claimant) -> Bool {
        if lhs.sample.rank != rhs.sample.rank {
            return lhs.sample.rank < rhs.sample.rank
        }
        if lhs.sample.time != rhs.sample.time {
            return lhs.sample.time > rhs.sample.time
        }
        return lhs.sample.deviceID < rhs.sample.deviceID
    }

    /// Adjacent credits of one Sample's claim joined into one.
    private static func coalesced(_ credits: [Credit]) -> [Credit] {
        var result: [Credit] = []
        for credit in credits {
            if var last = result.last, last.end == credit.start, last.deviceID == credit.deviceID, last.item == credit.item,
               last.isPassive == credit.isPassive, last.isReconstructed == credit.isReconstructed, last.sampleTime == credit.sampleTime
            {
                last.end = credit.end
                result[result.count - 1] = last
            } else {
                result.append(credit)
            }
        }
        return result
    }
}
