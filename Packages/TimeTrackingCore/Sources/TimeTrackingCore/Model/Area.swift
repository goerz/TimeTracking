// Area: a line of work inside one client, carrying the color (spec_data_and_sync.md §1.2).

public import Foundation

/// An area of a client. The general area is created with the client, is
/// named like it, sits at position 0, and can only change its color.
public struct Area: Identifiable, Hashable, Sendable {
    public var id: AreaID
    /// Never changes.
    public var clientID: ClientID
    public var name: String
    /// Fixed at creation.
    public var isGeneral: Bool
    /// `#RRGGBB`, uppercase.
    public var color: String
    /// Position within the client; the general area is always 0.
    public var sortOrder: Int
    /// Hidden from pickers and project creation; history keeps reporting.
    public var isRetired: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: AreaID = AreaID(),
        clientID: ClientID,
        name: String,
        isGeneral: Bool = false,
        color: String,
        sortOrder: Int = 0,
        isRetired: Bool = false,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.clientID = clientID
        self.name = name
        self.isGeneral = isGeneral
        self.color = color
        self.sortOrder = sortOrder
        self.isRetired = isRetired
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }

    /// The parsed color; `nil` only for a malformed synced value.
    public var areaColor: AreaColor? {
        try? AreaColor(color)
    }
}
