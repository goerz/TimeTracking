// ActivityBlockDetail: the detail-log record of a block
// (spec_data_and_sync.md §6, spec_activity_tracking.md §4.3).

public import Foundation

/// The detail of a block, read on the recording Mac only.
///
/// In `detail/YYYY-MM.jsonl` it is a block line with `items` uncut, plus
/// `urls` as `[time, browser, url, title]`, `files` as `[time, path]`, and
/// `presence` as `[time, state]` transitions in and around the block.
public struct ActivityBlockDetail: Sendable, Hashable {
    /// The id of the block this detail belongs to.
    public var blockID: ActivityBlock.ID
    /// Every item, before the summary cut.
    public var items: [ActivityItem]
    public var urls: [ActivityURLVisit]
    public var files: [ActivityFileChange]
    public var presence: [ActivityPresenceTransition]

    public init(
        blockID: ActivityBlock.ID,
        items: [ActivityItem],
        urls: [ActivityURLVisit] = [],
        files: [ActivityFileChange] = [],
        presence: [ActivityPresenceTransition] = []
    ) {
        self.blockID = blockID
        self.items = items
        self.urls = urls
        self.files = files
        self.presence = presence
    }
}

/// A visited URL of the detail log.
public struct ActivityURLVisit: Sendable, Hashable {
    public var time: Date
    /// The browser context, e.g. `safari`.
    public var browser: String
    public var url: String
    public var title: String

    public init(time: Date, browser: String, url: String, title: String) {
        self.time = time
        self.browser = browser
        self.url = url
        self.title = title
    }
}

/// A modified file of the detail log.
public struct ActivityFileChange: Sendable, Hashable {
    public var time: Date
    public var path: String

    public init(time: Date, path: String) {
        self.time = time
        self.path = path
    }
}

/// A presence transition of the detail log.
public struct ActivityPresenceTransition: Sendable, Hashable {
    public var time: Date
    public var state: TrackerPresenceState

    public init(time: Date, state: TrackerPresenceState) {
        self.time = time
        self.state = state
    }
}
