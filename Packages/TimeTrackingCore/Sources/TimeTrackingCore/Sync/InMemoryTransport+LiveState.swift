// InMemoryTransport+LiveState: the simulated zone's direct record read,
// for LiveStateReader in tests and -UITesting (data_and_sync.md §3.3,
// §4.3).

import Foundation

extension InMemoryTransport: LiveStateFetching {
    public func fetch(_ ref: SyncRecordRef) async throws -> SyncRecord? {
        try await server.checkReachable(device)
        return await server.record(ref)
    }
}
