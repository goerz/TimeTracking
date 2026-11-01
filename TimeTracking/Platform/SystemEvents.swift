// SystemEvents: input idle time, sleep, wake, lock, session, and power-off
// events for idle detection, the tracker warning, the Pomodoro, and
// reminders (spec_timer.md §5.2, §6.1, §7; spec_menubar.md §3, §5).

import AppKit
import CoreGraphics
import TimeTrackingCore

/// Samples input idleness every 10 s and forwards system events.
final class SystemEvents {
    private let app: AppModel
    private weak var statusItem: StatusItemController?
    private var observers: [NSObjectProtocol] = []
    private var sampling: Task<Void, Never>?
    private var checking: Task<Void, Never>?
    private(set) var isLocked = false
    private let workspace: NotificationCenter
    private let distributed: NotificationCenter

    /// `workspace` and `distributed` default to the system's centers; tests
    /// pass their own to post sleep and wake.
    init(
        app: AppModel,
        statusItem: StatusItemController?,
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributed: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.app = app
        self.statusItem = statusItem
        self.workspace = workspace
        self.distributed = distributed
    }

    /// Observes the system events; `polling` also starts the 10-second
    /// idle sampling and the 30-second check.
    func start(polling: Bool = true) {
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.event(.sleep) }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.event(.wake) }
            },
            workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.event(.sessionResigned) }
            },
            workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.event(.sessionActivated) }
            },
            workspace.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.event(.shutdown) }
            },
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.event(.lock) }
            },
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.event(.unlock) }
            },
        ]
        guard polling else {
            return
        }
        sampling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        checking = Task { [weak self] in
            while !Task.isCancelled {
                await self?.periodicCheck()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Seconds since the last input event of any kind.
    static var idleSeconds: TimeInterval {
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func sample() async {
        let state = app.tracker.state
        let presence = state.flatMap { $0.isRunning(at: app.clock.now) ? $0.presence : nil }
        await app.idle.sample(idleSeconds: Self.idleSeconds, presence: presence)
    }

    /// Every 30 s: the tracker warning and reminders.
    private func periodicCheck() async {
        await app.tracker.refresh()
        await app.reminders.check()
    }

    private func event(_ event: IdleSystemEvent) {
        let now = app.clock.now
        switch event {
        case .lock, .sleep, .sessionResigned:
            isLocked = true
            app.tracker.becameAbsent()
            statusItem?.setAsleep(event == .sleep)
        case .unlock, .wake, .sessionActivated:
            isLocked = false
            statusItem?.setAsleep(false)
            app.pomodoro.tick()
            Task { await app.tracker.becamePresent(at: now) }
        case .shutdown:
            break
        }
        Task { await app.idle.systemEvent(event, at: now) }
    }
}
