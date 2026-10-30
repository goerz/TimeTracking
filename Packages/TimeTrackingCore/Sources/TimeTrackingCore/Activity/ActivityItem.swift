// ActivityItem: one line of a block summary (spec_data_and_sync.md §6,
// spec_activity_tracking.md §2.2, §4.2).

/// An item of a block: context, subject, and detail with the seconds spent.
///
/// In the logs an item is the array `[context, subject, detail, seconds]`,
/// with `""` for no detail.
public struct ActivityItem: Sendable, Hashable, Codable {
    /// The kind of place, e.g. `tmux:paper` or `safari`.
    public var context: String
    /// The piece of work, e.g. a window, folder, or `github.com/owner/repo`.
    public var subject: String
    /// The thing in hand, e.g. `nvim notes.tex`; empty for none.
    public var detail: String
    /// Seconds spent on the item.
    public var seconds: Int

    public init(context: String, subject: String, detail: String, seconds: Int) {
        self.context = context
        self.subject = subject
        self.detail = detail
        self.seconds = seconds
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.context = try container.decode(String.self)
        self.subject = try container.decode(String.self)
        self.detail = try container.decode(String.self)
        self.seconds = try container.decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(context)
        try container.encode(subject)
        try container.encode(detail)
        try container.encode(seconds)
    }
}
