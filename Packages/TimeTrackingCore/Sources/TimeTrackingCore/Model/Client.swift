// Client: who the work is for (data_and_sync.md §1.1, §1.7).

public import Foundation

/// A client. Groups areas; has exactly one general area.
public struct Client: Identifiable, Hashable, Sendable {
    public var id: ClientID
    /// Non-empty after trimming; unique among live clients (folded).
    public var name: String
    public var createdAt: Date
    /// The last local change, millisecond precision; drives conflict resolution.
    public var modifiedAt: Date
    public var deletedAt: Date?
    /// True when none of its areas holds an active project. Derived by the
    /// queries that return clients, never stored.
    public var isRetired: Bool

    public init(
        id: ClientID = ClientID(),
        name: String,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil,
        isRetired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.isRetired = isRetired
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }
}
