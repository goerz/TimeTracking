// ChangeNotifier: the cross-process change signal `<APP_ID>.changed`
// (spec_data_and_sync.md §2.2, spec_architecture.md §1.5).

import Darwin
import Foundation
import notify
import Synchronization

/// Posts the change signal after a commit and delivers other writers' signals.
public protocol ChangeNotifier: Sendable {
    /// Posts one notification.
    func post()
    /// Notifications posted by other writers (not by this notifier).
    func notifications() -> AsyncStream<Void>
}

/// The Darwin notification `<APP_ID>.changed`, the only cross-process
/// change signal. Its own posts are recognized by a random token in the
/// notification state and not delivered back.
public final class DarwinChangeNotifier: ChangeNotifier {
    public let name: String
    private let token = UInt64.random(in: 1 ... UInt64.max)
    private let stateToken: Int32

    public init(name: String) {
        self.name = name
        var registration: Int32 = 0
        notify_register_check(name, &registration)
        self.stateToken = registration
    }

    /// The notifier of `identity`, `<APP_ID>.changed`.
    public convenience init(identity: AppIdentity) {
        self.init(name: identity.changeNotificationName)
    }

    deinit {
        notify_cancel(stateToken)
    }

    public func post() {
        notify_set_state(stateToken, token)
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
        let own = token
        let stateToken = stateToken
        handle.readabilityHandler = { handle in
            guard !handle.availableData.isEmpty else {
                return
            }
            var state: UInt64 = 0
            notify_get_state(stateToken, &state)
            if state != own {
                continuation.yield()
            }
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
