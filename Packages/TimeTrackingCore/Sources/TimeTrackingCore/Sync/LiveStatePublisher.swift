// LiveStatePublisher: this Mac's activity entry of LiveState, from the
// tracker's current.json (data_and_sync.md §4.2). Mac app only.

import Foundation

/// Copies the tracker fields of this Mac into `LiveState`.
///
/// Feed it the parsed `current.json` on every change and at least every
/// 30 seconds (`update(_:)`). Presence, `agentRunning`, and `health`
/// changes are written at once; `foreground` and `groupKey` changes at most
/// once per 30 seconds, a change inside the window being written at its end
/// with the values current then; a `lastTick` change alone writes nothing.
public actor LiveStatePublisher {
    /// The window of foreground and group-key writes.
    public static let foregroundInterval: TimeInterval = 30

    private let store: TimeStore
    private let deviceID: DeviceID
    /// This Mac's name, the entry's `device`.
    private let deviceName: String
    private let clock: any Clock
    private var published: LiveState.MacActivity?
    private var loaded = false
    private var lastForegroundWrite: Date?
    /// When a held-back foreground change is due.
    public private(set) var nextDue: Date?

    public init(store: TimeStore, deviceID: DeviceID, deviceName: String, clock: any Clock) {
        self.store = store
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.clock = clock
    }

    /// Re-evaluates the entry for `state` (`nil` without `current.json`)
    /// and writes it when the rules say so. Returns whether it wrote.
    @discardableResult
    public func update(_ state: TrackerState?) async throws -> Bool {
        let now = clock.now
        if !loaded {
            published = try await store.liveState().activity[deviceID.rawValue]
            loaded = true
        }
        guard let candidate = Self.activity(from: state, device: deviceName, previous: published, at: now) else {
            return false
        }
        guard let published else {
            try await write(candidate, foregroundChanged: true)
            return true
        }
        let immediate = candidate.presence != published.presence || candidate.since != published.since
            || candidate.agentRunning != published.agentRunning || candidate.health != published.health
            || candidate.device != published.device
        let foregroundChanged = candidate.foreground != published.foreground || candidate.groupKey != published.groupKey
        if !foregroundChanged {
            nextDue = nil
        }
        if immediate {
            try await write(candidate, foregroundChanged: foregroundChanged)
            return true
        }
        guard foregroundChanged else {
            return false
        }
        if let last = lastForegroundWrite, now < last + Self.foregroundInterval {
            nextDue = last + Self.foregroundInterval
            return false
        }
        try await write(candidate, foregroundChanged: true)
        return true
    }

    private func write(_ activity: LiveState.MacActivity, foregroundChanged: Bool) async throws {
        try await store.setLiveActivity(activity, for: deviceID)
        published = activity
        if foregroundChanged {
            lastForegroundWrite = activity.updatedAt
            nextDue = nil
        }
    }

    /// The entry `current.json` gives at `now`; without the file, the
    /// previous entry with `agentRunning` false, or nothing if none.
    static func activity(
        from state: TrackerState?,
        device: String,
        previous: LiveState.MacActivity?,
        at now: Date
    ) -> LiveState.MacActivity? {
        guard let state else {
            guard var previous, previous.agentRunning else {
                return previous
            }
            previous.agentRunning = false
            previous.updatedAt = now
            return previous
        }
        return LiveState.MacActivity(
            device: device,
            foreground: state.foreground,
            groupKey: state.block?.dominantWorkspace?.workspace,
            presence: state.presence.state.rawValue,
            since: state.presence.since,
            agentRunning: state.isRunning(at: now),
            lastTick: state.health.lastTick,
            health: state.health.sources.filter { $0.status != .active }.map(\.id),
            updatedAt: now
        )
    }
}
