// KnowledgeBackfill: samples reconstructed from the Knowledge store's app
// intervals for periods the agent was down (spec_activity_tracking.md §3.2).

import Foundation
import TimeTrackingCore

/// Turns `/app/usage` intervals into one sample per tick interval, so the
/// Blocker forms `knowledge` blocks by the same rules as live ones.
nonisolated enum KnowledgeBackfill {
    static func samples(
        apps: [KnowledgeAppInterval],
        displayOff: [DateInterval],
        in gap: DateInterval,
        rules: ExclusionRules,
        interval: TimeInterval
    ) -> [Sample] {
        var result: [Sample] = []
        for app in apps.sorted(by: { $0.start < $1.start }) where !rules.excludesApp(app.bundleID) {
            let start = max(app.start, gap.start)
            let end = min(app.end, gap.end)
            guard end > start else {
                continue
            }
            let context = contextName(app.bundleID)
            let item = SampleItem(context: context, subject: "", groupKey: context, app: app.bundleID)
            var time = start
            while time <= end {
                if !displayOff.contains(where: { $0.contains(time) }) {
                    result.append(Sample(time: time, state: .active, primary: item, bundleID: app.bundleID))
                }
                time = time.addingTimeInterval(interval)
            }
            if let last = result.last, end.timeIntervalSince(last.time) >= 1 {
                result.append(Sample(time: end, state: .active, primary: item, bundleID: app.bundleID))
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    /// The context name of a bundle identifier, as the live resolvers name it.
    static func contextName(_ bundleID: String) -> String {
        if let name = AppResolver.contextNames[bundleID] {
            return name
        }
        if let browser = BrowserApp.known[bundleID] {
            return browser.context
        }
        if let terminal = TerminalApp.known[bundleID] {
            return terminal.context
        }
        return (bundleID.split(separator: ".").last.map(String.init) ?? bundleID).lowercased()
    }
}
