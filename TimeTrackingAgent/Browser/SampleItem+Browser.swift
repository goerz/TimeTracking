// SampleItem+Browser: the item of a web page under the browser rules
// (spec_activity_tracking.md §3.3, §6.1, §6.2).

import TimeTrackingCore

extension SampleItem {
    /// The item of a page in the browser with context `context`: subject,
    /// detail, and group key from `parts`, or only the private marker under
    /// the browser's context when the page's domain is excluded.
    nonisolated init(browser context: String, parts: BrowserItemRules.Parts, app: String) {
        if parts.isExcluded {
            self.init(context: context, subject: ExclusionRules.privateMarker, groupKey: context, app: app)
        } else {
            self.init(context: context, subject: parts.subject, detail: parts.detail, groupKey: parts.groupKey, app: app)
        }
    }
}
