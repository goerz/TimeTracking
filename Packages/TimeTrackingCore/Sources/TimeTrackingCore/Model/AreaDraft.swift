// Drafts and changes of clients, areas, and projects (spec_data_and_sync.md §1.1 to §1.3, §7.1).

import Foundation

/// A new non-general area.
public struct AreaDraft: Hashable, Sendable {
    public var clientID: ClientID
    public var name: String
    /// `#RRGGBB`; the default rule when `nil`.
    public var color: String?
    /// After the client's last area when `nil`.
    public var sortOrder: Int?

    public init(clientID: ClientID, name: String, color: String? = nil, sortOrder: Int? = nil) {
        self.clientID = clientID
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
    }
}

/// The fields `updateArea(_:_:)` changes; `nil` leaves a field as it is.
public struct AreaChange: Hashable, Sendable {
    public var name: String?
    public var color: String?
    public var sortOrder: Int?
    // swiftlint:disable:next discouraged_optional_boolean
    public var retired: Bool?

    // swiftlint:disable:next discouraged_optional_boolean
    public init(name: String? = nil, color: String? = nil, sortOrder: Int? = nil, retired: Bool? = nil) {
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.retired = retired
    }
}

/// A new project.
public struct ProjectDraft: Hashable, Sendable {
    public var id: ProjectID?
    public var areaID: AreaID
    public var name: String

    public init(id: ProjectID? = nil, areaID: AreaID, name: String) {
        self.id = id
        self.areaID = areaID
        self.name = name
    }
}

/// The fields `updateProject(_:_:)` changes; `nil` leaves a field as it is.
public struct ProjectChange: Hashable, Sendable {
    public var name: String?
    public var areaID: AreaID?

    public init(name: String? = nil, areaID: AreaID? = nil) {
        self.name = name
        self.areaID = areaID
    }
}
