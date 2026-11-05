// LiveStateReader: fetches the LiveState record without the sync engine,
// for the widget timeline providers (data_and_sync.md §4.3).

public import Foundation

/// A transport that can read one record directly.
public protocol LiveStateFetching: Sendable {
    /// The server's copy of `ref`, or `nil` when it has none.
    func fetch(_ ref: SyncRecordRef) async throws -> SyncRecord?
}

/// Reads the server's `LiveState` with a timeout.
public struct LiveStateReader: Sendable {
    public let transport: any LiveStateFetching
    /// Waits for the timeout; `Task.sleep` unless a test replaces it.
    private let sleep: @Sendable (Duration) async throws -> Void

    @preconcurrency
    public init(
        transport: any LiveStateFetching,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.transport = transport
        self.sleep = sleep
    }

    /// The record as a `LiveState` (empty when the server has none); throws
    /// `SyncTransportError.networkUnavailable` after `timeout` seconds.
    public func fetch(timeout: TimeInterval) async throws -> LiveState {
        let transport = transport
        let sleep = sleep
        return try await withThrowingTaskGroup(of: LiveState?.self) { group in
            group.addTask {
                let record = try await transport.fetch(SyncRecordRef(.liveState, "LiveState"))
                return record.map(LiveState.init(record:)) ?? LiveState()
            }
            group.addTask {
                try await sleep(.seconds(timeout))
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let state = first else {
                throw SyncTransportError.networkUnavailable
            }
            return state
        }
    }
}

extension LiveState {
    /// The state a `LiveState` sync record carries.
    public init(record: SyncRecord) {
        self.init(
            running: Self.running(json: record["running"]?.string),
            changedAt: record["changedAt"]?.date.map { Time.wholeMillis($0) },
            activity: Self.activity(json: record["activity"]?.string)
        )
    }
}
