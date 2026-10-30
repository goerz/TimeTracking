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
    /// Another process held the write lock past the busy timeout.
    case busy
    /// SQLite failed; the message is for logs.
    case database(String)

    /// A plain sentence without case names; views show `UserMessage`, and
    /// logs use `String(describing:)` for the details.
    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case .duplicateName: "That name is already used."
        case .projectArchived: "This project is archived. Restore it to use it."
        case .areaRetired: "This area is retired. Reactivate it to use it."
        case .generalArea: "A client's general area can't be renamed."
        case .activeProjects: "This area still has active projects."
        case .invalidColor: "That color is not valid."
        case .endBeforeStart: "The end is before the start."
        case .inFuture: "Times can't be in the future."
        case .referenced: "This is still in use."
        case .unknownID: "This was deleted, perhaps on another device."
        case .retentionExpired: "This was deleted too long ago to restore."
        case let .invalidDocument(path, reason): "This file is not a valid TimeTracking export (\(path): \(reason))."
        case .newerSchema: "Your time data was saved by a newer version of the app. Update the app."
        case .readOnly: "Your time data can't be changed here."
        case .busy: "Your time data is busy in another app. Try again."
        case .database: "Your time data couldn't be read or saved. Try again."
        }
    }
}
