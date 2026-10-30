// AgentEngine+Detail: the detail-log record of a closed block
// (spec_activity_tracking.md §3.2, §3.3, §3.4, §4.3).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// The detail of `closed`: browser visits in its range (Safari's
    /// `History.db` with `origin = 0` and every Chromium profile, else the
    /// sampled URLs), modified files, presence transitions since the
    /// previous detail line, and Safari dwell times from the Knowledge store.
    func detail(for closed: ClosedBlock) -> ActivityBlockDetail {
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
        urls.sort { ($0.time, $0.url) < ($1.time, $1.url) }
        let windowStart = lastDetailEnd.map { min($0, block.start) } ?? block.start
        var presence = transitions.filter { $0.time >= windowStart && $0.time <= block.end }
        if let before = transitions.last(where: { $0.time < windowStart }) {
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
        let raw = ActivityBlockDetail(
            blockID: block.id,
            items: closed.detailItems,
            urls: urls,
            files: fileChanges.changes(from: block.start, to: block.end),
            presence: presence,
            dwell: dwell
        )
        return resolveContext().exclusions.reapplied(to: raw, contexts: closed.contexts)
    }
}
