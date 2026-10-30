// InMemoryDeviceEventServer: the zone `ActivityEvents` in memory, for tests and
// UI testing: an uploader for the iOS flush and a DeviceEventSource for the
// Mac agent (spec_data_and_sync.md §6, spec_architecture.md §3.3).

public import Foundation

/// A server holding device events by record name. Saving a name again
/// replaces the event in place, as CloudKit does; the change token is the
/// position in the change log.
public actor InMemoryDeviceEventServer {
    private var log: [(position: Int, name: String)] = []
    private var counter = 0
    private var events: [String: DeviceEvent] = [:]
    private var failing: (any Error)?

    public init() {}

    /// Makes every upload and fetch throw `error` until set to `nil`.
    public func setFailing(_ error: (any Error)?) {
        failing = error
    }

    /// Saves `batch` (the iOS uploader).
    public func upload(_ batch: [DeviceEvent]) throws {
        if let failing {
            throw failing
        }
        for event in batch {
            log.removeAll { $0.name == event.recordName }
            counter += 1
            log.append((counter, event.recordName))
            events[event.recordName] = event
        }
    }

    /// Every stored event, oldest first.
    public var all: [DeviceEvent] {
        events.values.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }
    }

    func changes(after position: Int) throws -> ([DeviceEvent], Int) {
        if let failing {
            throw failing
        }
        let names = log.filter { $0.position > position }.map(\.name)
        return (names.compactMap { events[$0] }, counter)
    }

    func purge(before date: Date) {
        let old = Set(events.values.filter { $0.time < date }.map(\.recordName))
        log.removeAll { old.contains($0.name) }
        for name in old {
            events[name] = nil
        }
    }

    /// The Mac side.
    public nonisolated var source: InMemoryDeviceEventSource {
        InMemoryDeviceEventSource(server: self)
    }
}

/// `DeviceEventSource` over an `InMemoryDeviceEventServer`.
public struct InMemoryDeviceEventSource: DeviceEventSource {
    public let server: InMemoryDeviceEventServer

    public func events(since token: ChangeToken?) async throws -> ([DeviceEvent], ChangeToken) {
        let position = token.flatMap { Int(String(decoding: $0.data, as: UTF8.self)) } ?? 0
        let (events, next) = try await server.changes(after: position)
        return (events, ChangeToken(data: Data(String(next).utf8)))
    }

    // The protocol's purge throws; this one cannot fail.
    // swiftlint:disable:next unneeded_throws_rethrows
    public func purge(before date: Date) async throws {
        await server.purge(before: date)
    }

    public var changes: AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
