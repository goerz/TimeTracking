// WidgetPushSender: when and to whom the Mac app sends WidgetKit pushes
// (spec_data_and_sync.md §4.3). Runs only in the Mac app.

public import Foundation
import os

/// What the settings window shows about widget pushes.
public enum WidgetPushStatus: Hashable, Sendable {
    /// No APNs key installed: no pushes.
    case noKey
    case idle(lastSentAt: Date?)
    case failing(String)
}

/// Pushes to every iPhone and iPad `Device` with a widget push token:
/// at once after a confirmed own `LiveState` save or an applied fetched
/// `LiveState` whose running part changed; activity-only saves at most once
/// per 60 seconds per token, a later one at the window's end
/// (`sendDue()`).
public actor WidgetPushSender {
    /// The window of activity-only pushes per token.
    public static let activityInterval: TimeInterval = 60

    private let store: TimeStore
    private let client: any WidgetPushing
    private let clock: any Clock
    public private(set) var status: WidgetPushStatus = .idle(lastSentAt: nil)
    /// The last push to each token.
    private var lastSent: [String: Date] = [:]
    /// Activity-only pushes waiting for their window: token → due time.
    private var pending: [String: Date] = [:]
    /// The running part of the last confirmed own save, once there was one.
    private var lastSavedRunning: String?
    private var hasSaved = false
    private var statusHandler: (@Sendable (WidgetPushStatus) -> Void)?
    private static let logger = Logging.logger(category: "Push")

    public init(store: TimeStore, client: any WidgetPushing, clock: any Clock) {
        self.store = store
        self.client = client
        self.clock = clock
    }

    /// Called on every status change.
    @preconcurrency
    public func onStatus(_ handler: @escaping @Sendable (WidgetPushStatus) -> Void) {
        statusHandler = handler
        handler(status)
    }

    /// The earliest due time of a waiting activity-only push.
    public var nextDue: Date? {
        pending.values.min()
    }

    /// Reacts to the sync engine's `LiveState` events.
    public func handle(_ event: LiveStateSyncEvent) async {
        switch event {
        case let .saved(state):
            let running = LiveState.runningJSON(state.running)
            let runningChanged = !hasSaved || lastSavedRunning != running
            lastSavedRunning = running
            hasSaved = true
            await push(runningPart: runningChanged)
        case let .fetched(_, runningChanged):
            if runningChanged {
                await push(runningPart: true)
            }
        }
    }

    /// Sends the activity-only pushes whose window has ended.
    public func sendDue() async {
        let now = clock.now
        let due = pending.filter { $0.value <= now }.keys.sorted()
        guard !due.isEmpty else {
            return
        }
        guard await client.hasKey() else {
            pending = [:]
            setStatus(.noKey)
            return
        }
        for token in due {
            pending[token] = nil
            await send(to: token)
        }
    }

    private func push(runningPart: Bool) async {
        guard await client.hasKey() else {
            pending = [:]
            setStatus(.noKey)
            return
        }
        let tokens: [String]
        do {
            tokens = try await store.devices()
                .filter { $0.platform != .mac }
                .compactMap(\.widgetPushToken)
                .filter { !$0.isEmpty }
        } catch {
            Self.logger.error("Widget push failed: \(String(describing: error), privacy: .public)")
            setStatus(.failing(error.localizedDescription))
            return
        }
        let now = clock.now
        for token in Set(tokens).sorted() {
            if runningPart {
                pending[token] = nil
                await send(to: token)
            } else if let last = lastSent[token], now.timeIntervalSince(last) < Self.activityInterval {
                pending[token] = last + Self.activityInterval
            } else {
                await send(to: token)
            }
        }
    }

    private func send(to token: String) async {
        let now = clock.now
        lastSent[token] = now
        do {
            let response = try await client.pushWidgets(to: token)
            if response.isSuccess {
                setStatus(.idle(lastSentAt: now))
            } else {
                let reason = response.reason ?? "HTTP \(response.status)"
                Self.logger.error("Widget push failed: \(reason, privacy: .public)")
                setStatus(.failing(reason))
            }
        } catch {
            Self.logger.error("Widget push failed: \(error.localizedDescription, privacy: .public)")
            setStatus(error == .noKey ? .noKey : .failing(error.localizedDescription))
        }
    }

    private func setStatus(_ new: WidgetPushStatus) {
        guard new != status else {
            return
        }
        status = new
        statusHandler?(new)
    }
}
