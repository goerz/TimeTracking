// Identifier: typed record ids, lowercase UUIDs (spec_data_and_sync.md §1).

public import Foundation

/// A typed identifier: a UUID tagged with the entity it names, so an
/// `EntryID` cannot be passed where a `ProjectID` is expected.
///
/// Encodes as the lowercase UUID string. Ordering compares that string,
/// which is the "greater id" of the conflict and running-entry rules.
public struct Identifier<Entity>: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let uuid: UUID

    public init(_ uuid: UUID) {
        self.uuid = uuid
    }

    /// A new random (version 4) identifier.
    public init() {
        self.uuid = UUID()
    }

    /// Parses a UUID string in either case.
    public init?(_ string: String) {
        guard let uuid = UUID(uuidString: string) else {
            return nil
        }
        self.uuid = uuid
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a UUID: \(string)")
        }
        self.uuid = uuid
    }

    /// The lowercase UUID string, as stored and synced.
    public var rawValue: String {
        uuid.uuidString.lowercased()
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public typealias ClientID = Identifier<Client>
public typealias AreaID = Identifier<Area>
public typealias ProjectID = Identifier<Project>
public typealias EntryID = Identifier<TimeEntry>
public typealias DeviceID = Identifier<Device>
public typealias FeedbackID = Identifier<SuggestionFeedback>
