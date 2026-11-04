// ChangeNotifier: the cross-process change signal `<APP_ID>.changed`
// (spec_data_and_sync.md §2.2, spec_architecture.md §1.5).

import Darwin
import Foundation
import notify
import Synchronization

/// Posts the change signal after a commit and delivers the writers' signals.
public protocol ChangeNotifier: Sendable {
    /// Posts one notification.
    func post()
    /// Notifications posted by other writers; a notifier may also deliver
    /// its own posts, which the store tells apart (`PRAGMA data_version`).
    func notifications() -> AsyncStream<Void>
}

/// The Darwin notification `<APP_ID>.changed`, the only cross-process
/// change signal. Every post reaches every listener, its own included:
/// the notification carries no sender, and posts arriving close together
/// are delivered as one, so filtering by sender would drop another
/// process's post that coalesced with this one's.
public final class DarwinChangeNotifier: ChangeNotifier {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    /// The notifier of `identity`, `<APP_ID>.changed`.
    public convenience init(identity: AppIdentity) {
        self.init(name: identity.changeNotificationName)
    }

    public func post() {
        notify_post(name)
    }

    public func notifications() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var descriptor: Int32 = -1
        var registration: Int32 = 0
        guard notify_register_file_descriptor(name, &descriptor, 0, &registration) == NOTIFY_STATUS_OK else {
            continuation.finish()
            return stream
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        handle.readabilityHandler = { handle in
            guard !handle.availableData.isEmpty else {
                return
            }
            continuation.yield()
        }
        let registered = registration
        continuation.onTermination = { _ in
            handle.readabilityHandler = nil
            notify_cancel(registered)
        }
        return stream
    }
}

/// An in-process stand-in for the Darwin notification: endpoints of one
/// hub see each other's posts, as separate processes would. Counts posts.
public final class InMemoryChangeNotifier: ChangeNotifier {
    /// Connects several notifiers like processes sharing one notification name.
    public final class Hub: Sendable {
        let endpoints = Mutex<[ObjectIdentifier: AsyncStream<Void>.Continuation]>([:])

        public init() {}

        func post(from sender: ObjectIdentifier) {
            for (id, continuation) in endpoints.withLock({ $0 }) where id != sender {
                continuation.yield()
            }
        }
    }

    private let hub: Hub
    private let posts = Mutex(0)

    public init(hub: Hub = Hub()) {
        self.hub = hub
    }

    /// The number of `post()` calls so far.
    public var postCount: Int {
        posts.withLock { $0 }
    }

    public func post() {
        posts.withLock { $0 += 1 }
        hub.post(from: ObjectIdentifier(self))
    }

    public func notifications() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = ObjectIdentifier(self)
        hub.endpoints.withLock { $0[id] = continuation }
        continuation.onTermination = { [hub] _ in
            hub.endpoints.withLock { _ = $0.removeValue(forKey: id) }
        }
        return stream
    }
}
