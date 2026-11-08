// InMemoryDeviceEventServer: the zone `ActivityEvents` in memory, for tests and
// UI testing: an uploader for the iOS flush and a DeviceEventSource for the
// Mac agent (data_and_sync.md §6, architecture.md §3.3).

public import Foundation

/// A server holding device events by record name. Saving a name again
/// replaces the event in place, as CloudKit does; the change token is the
/// position in the change log.
public actor InMemoryDeviceEventServer {
    private var log: [(position: Int, name: String)] = []
    private var counter = 0
    private var events: [String: DeviceEvent] = [:]
    /// Records of another app version, which the Mac can't read, by name.
    private var unreadable: [String: Date] = [:]
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

    /// Saves a record of another app version at `time` under `name`, as
    /// an older iOS app's would be.
    public func uploadUnreadable(_ name: String, at time: Date) {
        log.removeAll { $0.name == name }
        counter += 1
        log.append((counter, name))
        unreadable[name] = time
    }

    /// The names of the stored records of another app version.
    public var unreadableNames: Set<String> {
        Set(unreadable.keys)
    }

    /// Every stored event, oldest first.
    public var all: [DeviceEvent] {
        events.values.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }
    }

    func changes(after position: Int) throws -> DeviceEventBatch {
        if let failing {
            throw failing
        }
        let names = log.filter { $0.position > position }.map(\.name)
        return DeviceEventBatch(
            events: names.compactMap { events[$0] },
            token: ChangeToken(data: Data(String(counter).utf8)),
            unreadable: names.count { unreadable[$0] != nil }
        )
    }

    func purge(before date: Date) {
        let kept = DeviceEvent.kept(of: Array(events.values), before: date)
        let old = Set(events.values.filter { $0.time < date && !kept.contains($0.recordName) }.map(\.recordName))
            .union(unreadable.filter { $0.value < date }.keys)
        log.removeAll { old.contains($0.name) }
        for name in old {
            events[name] = nil
            unreadable[name] = nil
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

    public func events(since token: ChangeToken?) async throws -> DeviceEventBatch {
        let position = token.flatMap { Int(String(decoding: $0.data, as: UTF8.self)) } ?? 0
        return try await server.changes(after: position)
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
