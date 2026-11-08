// DeviceEventSource: how the Mac agent receives device events
// (data_and_sync.md §6).

public import Foundation

/// The device events of iPhones and iPads, read by the Mac agent only.
public protocol DeviceEventSource: Sendable {
    /// The events after `token` (all with `nil`) and the token to pass next.
    func events(since token: ChangeToken?) async throws -> DeviceEventBatch
    /// Deletes the events older than `date` (the cutoff date), except the
    /// ones `DeviceEvent.kept(of:before:)` keeps.
    func purge(before date: Date) async throws
    /// Fires when new events may be available.
    var changes: AsyncStream<Void> { get }
}

/// An opaque position in a stream of changes, such as a CloudKit server
/// change token in archived form.
public struct ChangeToken: Sendable, Hashable, Codable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }
}

/// What one read of the change feed found.
public struct DeviceEventBatch: Sendable {
    public var events: [DeviceEvent]
    /// The token to pass next.
    public var token: ChangeToken
    /// Device event records this version can't read (from an iOS app of
    /// another version), skipped: the token moves past them.
    public var unreadable: Int

    public init(events: [DeviceEvent], token: ChangeToken, unreadable: Int = 0) {
        self.events = events
        self.token = token
        self.unreadable = unreadable
    }
}
