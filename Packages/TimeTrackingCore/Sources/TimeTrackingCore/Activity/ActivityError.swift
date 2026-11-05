// ActivityError: the errors of the Activity module (data_and_sync.md §6,
// architecture.md §4.1).

public import Foundation

/// Errors reading or writing the activity files.
public enum ActivityError: Error, Equatable, LocalizedError {
    /// A block-log or detail-log line that is not a valid object.
    case malformedLine(String)
    /// A `settings.toml` that cannot be read; the message is the sentence
    /// the Tracker pane shows under the settings file.
    case invalidSettings(String)
    /// A `current.json` that cannot be read.
    case invalidState(String)
    /// A file operation failed.
    case fileSystem(String)

    public var errorDescription: String? {
        switch self {
        case let .malformedLine(reason):
            "Malformed activity log line: \(reason)"
        case let .invalidSettings(message):
            message
        case let .invalidState(reason):
            "The tracker state cannot be read: \(reason)"
        case let .fileSystem(reason):
            "An activity file operation failed: \(reason)"
        }
    }
}
