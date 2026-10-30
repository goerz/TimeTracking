// StoreError: the errors of every store write (spec_data_and_sync.md §7.1).

import Foundation

/// Why a store operation failed. User-visible text comes from the view layer.
public enum StoreError: Error, Equatable, Sendable, LocalizedError {
    case emptyName
    case duplicateName
    case projectArchived
    case areaRetired
    case generalArea
    case activeProjects
    case invalidColor
    case endBeforeStart
    case inFuture
    case referenced
    case unknownID
    case retentionExpired
    /// An import document failed validation at `path` (`entries[1041].end`).
    case invalidDocument(path: String, reason: String)
    /// The file's `meta.schema_version` is newer than this library knows.
    case newerSchema(version: Int)
    /// The store was opened read-only.
    case readOnly
    /// SQLite failed; the message is for logs.
    case database(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidDocument(path, reason):
            "Invalid document at \(path): \(reason)"
        case let .newerSchema(version):
            "The store has schema version \(version), newer than this build supports."
        case let .database(message):
            "Database error: \(message)"
        default:
            "Store error: \(self)"
        }
    }
}
