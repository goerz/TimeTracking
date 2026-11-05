// Project: a unit of work inside one area (data_and_sync.md §1.3).

public import Foundation

/// A project. Its color is its area's; it has none of its own.
public struct Project: Identifiable, Hashable, Sendable {
    public var id: ProjectID
    /// May change, also to another client's area.
    public var areaID: AreaID
    /// Unique among the client's live projects (folded).
    public var name: String
    /// Hidden from pickers and autocompletion; entries are kept.
    public var isArchived: Bool
    /// Set when archived, cleared when restored.
    public var archivedAt: Date?
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: ProjectID = ProjectID(),
        areaID: AreaID,
        name: String,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.areaID = areaID
        self.name = name
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }

    /// Live and not archived.
    public var isActive: Bool {
        !isArchived && deletedAt == nil
    }
}
