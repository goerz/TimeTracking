// WidgetLiveResolver: the running state every widget and control provider
// uses (spec_ios.md §4, item 2): the store's `live_state` row, the last
// resolved state in the App Group, and a direct CloudKit fetch unless one ran
// less than 10 s ago or the app wrote the running entry less than 5 s ago.

public import Foundation

/// Resolves the `LiveState` for a timeline or control provider.
public struct WidgetLiveResolver: Sendable {
    /// A fetch younger than this is reused (one push reloads several kinds).
    public static let fetchReuse: TimeInterval = 10
    /// An app write younger than this is reused.
    public static let writeReuse: TimeInterval = 5
    /// How long a provider waits for CloudKit.
    public static let fetchTimeout: TimeInterval = 5

    /// What a provider builds from.
    public struct Resolution: Hashable, Sendable {
        public var liveState: LiveState
        /// Whether CloudKit was asked.
        public var fetched: Bool
        /// Whether the running entry differs from the last resolved one, so
        /// the provider reloads the timer control.
        public var runningChanged: Bool
    }

    public let shared: WidgetSharedState
    /// `nil` without CloudKit (UI testing, ad-hoc builds): never fetches.
    public let reader: LiveStateReader?
    public let clock: any Clock

    public init(shared: WidgetSharedState, reader: LiveStateReader?, clock: any Clock) {
        self.shared = shared
        self.reader = reader
        self.clock = clock
    }

    /// Merges `local` (the store's row, if the store is readable), the last
    /// resolved state, and a fetch when due; records the result.
    public func resolve(local: LiveState?) async -> Resolution {
        let now = clock.now
        let cached = shared.liveState
        var state = [local, cached].compactMap(\.self).reduce(LiveState()) { $0.merged(with: $1) }
        var fetched = false
        if let reader, isFetchDue(at: now) {
            fetched = true
            shared.lastFetchAt = now
            if let remote = try? await reader.fetch(timeout: Self.fetchTimeout) {
                state = state.merged(with: remote)
            }
        }
        shared.liveState = state
        let runningChanged = state.running?.entryID != cached?.running?.entryID
        return Resolution(liveState: state, fetched: fetched, runningChanged: runningChanged)
    }

    /// Whether neither a recent fetch nor a recent app write can be reused.
    public func isFetchDue(at now: Date) -> Bool {
        if let last = shared.lastFetchAt, now.timeIntervalSince(last) < Self.fetchReuse, now >= last {
            return false
        }
        if let write = shared.lastAppWriteAt, now.timeIntervalSince(write) < Self.writeReuse, now >= write {
            return false
        }
        return true
    }
}
