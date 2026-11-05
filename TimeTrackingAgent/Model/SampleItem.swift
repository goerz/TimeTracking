// SampleItem: one item of a sample, with its derived group key
// (activity_tracking.md §2.2, §2.4).

/// What attention is on: context, subject, detail, and the derived group key.
///
/// `app` is the bundle identifier (or process name) the context maps to in
/// the block log header.
nonisolated struct SampleItem: Hashable, Sendable {
    var context: String
    var subject: String
    var detail: String
    var groupKey: String
    var app: String

    init(context: String, subject: String, detail: String = "", groupKey: String, app: String) {
        self.context = context
        self.subject = subject
        self.detail = detail
        self.groupKey = groupKey
        self.app = app
    }

    /// The `[context, subject, detail]` key that summaries sum over.
    var key: ItemKey {
        ItemKey(context: context, subject: subject, detail: detail)
    }
}

/// The identity of an item in a summary; `device` is set where a summary
/// keeps the devices apart.
nonisolated struct ItemKey: Hashable, Sendable {
    var context: String
    var subject: String
    var detail: String
    var device = ""
}
