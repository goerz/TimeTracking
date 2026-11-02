// AgentEngine+Detail: the detail-log record of a closed block
// (spec_activity_tracking.md §3.2, §3.3, §3.4, §4.3).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// The detail of `closed`: browser visits in its range (Safari's
    /// `History.db` with `origin = 0` and every Chromium profile, else the
    /// sampled URLs), modified files, presence transitions since `since`
    /// (the end of the previous block) with the state in effect before
    /// when it began that day,
    /// and Safari dwell times from the Knowledge store; with the entries of
    /// `pool` (the day's old detail lines) that fall in the same ranges.
    func detail(for closed: ClosedBlock, since: Date, pool: DetailPool) -> ActivityBlockDetail {
        let block = closed.block
        var urls: [ActivityURLVisit] = []
        let safari = environment.history.safariVisits(from: block.start, to: block.end, origin: 0) ?? []
        let chromium = environment.history.chromiumVisits(from: block.start, to: block.end)
        for visit in (safari + chromium).sorted(by: { ($0.time, $0.url) < ($1.time, $1.url) }) {
            urls.append(ActivityURLVisit(time: visit.time, browser: visit.browser, url: visit.url, title: visit.title))
        }
        let visited = Set(urls.map(\.url))
        var lastURL = ""
        for row in (try? store.rows(from: block.start, to: block.end.addingTimeInterval(1))) ?? [] {
            let sample = row.sample
            guard !sample.url.isEmpty, sample.url != lastURL, let browser = sample.primary?.context else {
                continue
            }
            lastURL = sample.url
            if !visited.contains(sample.url) {
                urls.append(ActivityURLVisit(time: sample.time, browser: browser, url: sample.url, title: sample.title))
            }
        }
        let inBlock = { (time: Date) in time >= block.start && time <= block.end }
        urls = Self.union(urls, pool.urls.filter { inBlock($0.time) }) { ($0.time, $0.url) < ($1.time, $1.url) }
        let windowStart = min(since, block.start)
        let allTransitions = Self.union(transitions, pool.presence) { $0.time < $1.time }
        var presence = allTransitions.filter { $0.time >= windowStart && $0.time <= block.end }
        // The state in effect before, unless it began on an earlier date.
        let dayStart = ActivityTimestamp.startOfDay(block.start, timeZone: environment.timeZone)
        if let before = allTransitions.last(where: { $0.time < windowStart }), before.time >= dayStart {
            presence.insert(before, at: 0)
        }
        var dwell: [ActivityDwell] = []
        if health.status(.knowledge) == .active, case let .data(_, web, _) = environment.knowledge.read(from: block.start, to: block.end) {
            for interval in web {
                let start = max(interval.start, block.start)
                let seconds = Int(min(interval.end, block.end).timeIntervalSince(start))
                if seconds > 0 {
                    dwell.append(ActivityDwell(time: start, url: interval.url, seconds: seconds))
                }
            }
        }
        let recorded = fileChanges.changes(from: block.start, to: block.end)
        let files = Self.union(recorded, pool.files.filter { inBlock($0.time) }) { ($0.time, $0.path) < ($1.time, $1.path) }
        dwell = Self.union(dwell, pool.dwell.filter { inBlock($0.time) }) { ($0.time, $0.url) < ($1.time, $1.url) }
        let raw = ActivityBlockDetail(
            blockID: block.id,
            items: closed.detailItems,
            urls: urls,
            files: files,
            presence: presence,
            dwell: dwell
        )
        return resolveContext().exclusions.reapplied(to: raw, contexts: closed.contexts)
    }

    /// The entries of both lists once each, ordered by `less`.
    static func union<Entry: Hashable>(_ first: [Entry], _ second: [Entry], by less: (Entry, Entry) -> Bool) -> [Entry] {
        var seen = Set<Entry>()
        return (first + second).filter { seen.insert($0).inserted }.sorted(by: less)
    }
}
