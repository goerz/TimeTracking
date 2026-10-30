// DeviceEventSource: how the Mac agent receives device events
// (spec_data_and_sync.md §6).

public import Foundation

/// The device events of iPhones and iPads, read by the Mac agent only.
public protocol DeviceEventSource: Sendable {
    /// The events after `token` (all with `nil`) and the token to pass next.
    func events(since token: ChangeToken?) async throws -> ([DeviceEvent], ChangeToken)
    /// Deletes events older than `date` (the agent keeps 90 days).
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
