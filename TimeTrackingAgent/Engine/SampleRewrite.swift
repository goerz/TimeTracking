// SampleRewrite: the current exclusions applied to a stored sample for
// `reapply-exclusions` (activity_tracking.md §7.2, §7.3).

import Foundation
import TimeTrackingCore

/// Applies the current exclusions to a stored sample.
nonisolated enum SampleRewrite {
    static func reapplied(_ sample: Sample, rules: ExclusionRules) -> Sample {
        var result = sample
        if !sample.bundleID.isEmpty, rules.excludesApp(sample.bundleID) {
            return Sample(time: sample.time, state: sample.state, event: sample.event)
        }
        result.primary = sample.primary.flatMap { reapplied($0, bundleID: sample.bundleID, rules: rules) }
        result.secondaries = sample.secondaries.compactMap { reapplied($0, bundleID: $0.app, rules: rules) }
        if rules.excludesDomain(sample.url) {
            result.url = ""
            result.title = ""
        } else if rules.isPrivateDomain(sample.url), let components = URLComponents(string: sample.url), let host = components.host {
            result.url = "\(components.scheme ?? "https")://\(host)"
            result.title = ""
        }
        if rules.excludesTitle(result.title) {
            result.title = ""
        }
        if result.primary?.subject == ExclusionRules.privateMarker {
            result.url = ""
            result.title = ""
        }
        return result
    }

    static func reapplied(_ item: SampleItem, bundleID: String, rules: ExclusionRules) -> SampleItem? {
        let recorded = ActivityItem(context: item.context, subject: item.subject, detail: item.detail, seconds: 0, device: "")
        guard let kept = rules.reapplied(to: recorded, bundleIdentifier: bundleID) else {
            return nil
        }
        var result = item
        result.context = kept.context
        result.subject = kept.subject
        result.detail = kept.detail
        if kept.context != item.context {
            result.groupKey = kept.context
        } else if kept.subject == ExclusionRules.privateMarker, kept.detail == ExclusionRules.privateMarker,
                  !item.isTmux
        {
            result.groupKey = ExclusionRules.privateGroupKey
        } else if kept.subject == ExclusionRules.privateMarker {
            result.groupKey = item.isTmux ? item.groupKey : item.context
        } else if kept.subject != item.subject, rules.isPrivateDomain(kept.subject) {
            result.groupKey = kept.subject
        }
        return result
    }
}
