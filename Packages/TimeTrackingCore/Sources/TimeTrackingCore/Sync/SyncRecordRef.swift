// Record types and references of the sync layer (spec_data_and_sync.md §3.1).

import Foundation

/// The CloudKit record types of zone `TimeTracking`.
public enum SyncRecordType: String, Codable, Sendable, CaseIterable {
    case client = "Client"
    case area = "Area"
    case project = "Project"
    case timeEntry = "TimeEntry"
    case setting = "Setting"
    case device = "Device"
    case suggestionFeedback = "SuggestionFeedback"
    case liveState = "LiveState"
}

/// A record's type and name: the UUID, the setting key, or `LiveState`.
public struct SyncRecordRef: Hashable, Sendable, Codable, CustomStringConvertible {
    public var type: SyncRecordType
    public var name: String

    public init(_ type: SyncRecordType, _ name: String) {
        self.type = type
        self.name = name
    }

    public var description: String {
        "\(type.rawValue)/\(name)"
    }
}
