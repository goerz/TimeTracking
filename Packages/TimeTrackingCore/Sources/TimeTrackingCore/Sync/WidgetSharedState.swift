// WidgetSharedState: what the iOS app and its widget extension share in the
// App Group besides the store: the last resolved LiveState, the fetch and
// write times of the resolver, the widget push token, and whether the first
// sync has delivered the store (ios.md §3.1, §4).

public import Foundation

/// Values in the App Group's `UserDefaults` suite, read and written by the
/// app and the widget extension.
public struct WidgetSharedState: Sendable {
    private let suite: AppGroupDefaults

    private enum Key {
        /// The whole `LiveState` in one value, so a reader never sees the
        /// running part of one write with the activity of another.
        static let liveState = "widget.liveState"
        // The four keys of earlier builds, read until the first write.
        static let running = "widget.liveState.running"
        static let changedAt = "widget.liveState.changedAt"
        static let activity = "widget.liveState.activity"
        static let hasLiveState = "widget.liveState.present"
        static let lastFetchAt = "widget.lastFetchAt"
        static let lastAppWriteAt = "widget.lastAppWriteAt"
        static let pushToken = "widget.pushToken"
        static let hasPushToken = "widget.pushToken.present"
        static let setupComplete = "setupComplete"
        static let lastFlushAt = "collection.lastFlushAt"
    }

    public init(defaults: UserDefaults) {
        self.suite = AppGroupDefaults(defaults: defaults)
    }

    /// The App Group suite of `identity`, or the standard defaults.
    public init(identity: AppIdentity?) {
        self.suite = AppGroupDefaults(identity: identity)
    }

    private var defaults: UserDefaults {
        suite.defaults
    }

    /// The last `LiveState` the resolver or the app recorded, written and
    /// read as one value by the app and the widget extension.
    public var liveState: LiveState? {
        get {
            if let stored = defaults.dictionary(forKey: Key.liveState) {
                return LiveState(
                    running: LiveState.running(json: stored["running"] as? String),
                    changedAt: stored["changedAt"] as? Date,
                    activity: LiveState.activity(json: stored["activity"] as? String)
                )
            }
            guard defaults.bool(forKey: Key.hasLiveState) else {
                return nil
            }
            return LiveState(
                running: LiveState.running(json: defaults.string(forKey: Key.running)),
                changedAt: defaults.object(forKey: Key.changedAt) as? Date,
                activity: LiveState.activity(json: defaults.string(forKey: Key.activity))
            )
        }
        nonmutating set {
            for key in [Key.running, Key.changedAt, Key.activity, Key.hasLiveState] {
                defaults.removeObject(forKey: key)
            }
            guard let newValue else {
                defaults.removeObject(forKey: Key.liveState)
                return
            }
            var stored: [String: Any] = [:]
            stored["running"] = LiveState.runningJSON(newValue.running)
            stored["changedAt"] = newValue.changedAt
            stored["activity"] = LiveState.activityJSON(newValue.activity)
            defaults.set(stored, forKey: Key.liveState)
        }
    }

    /// When a provider last fetched `LiveState` from CloudKit.
    public var lastFetchAt: Date? {
        get { defaults.object(forKey: Key.lastFetchAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastFetchAt) }
    }

    /// When the app last wrote the running entry.
    public var lastAppWriteAt: Date? {
        get { defaults.object(forKey: Key.lastAppWriteAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastAppWriteAt) }
    }

    /// The widget push token (hex) the push handler stored: `.some(nil)`
    /// when no widget is installed, `nil` before the handler ever ran.
    public var pushToken: String?? {
        get {
            guard defaults.bool(forKey: Key.hasPushToken) else {
                return nil
            }
            return .some(defaults.string(forKey: Key.pushToken))
        }
        nonmutating set {
            switch newValue {
            case .none:
                defaults.removeObject(forKey: Key.hasPushToken)
                defaults.removeObject(forKey: Key.pushToken)
            case let .some(token):
                defaults.set(true, forKey: Key.hasPushToken)
                defaults.set(token, forKey: Key.pushToken)
            }
        }
    }

    /// The push handler's write: the hex token while widgets are installed,
    /// `.some(nil)` when none is.
    public func recordPushToken(_ token: Data, widgetCount: Int) {
        pushToken = .some(widgetCount == 0 ? nil : token.hexString)
    }

    /// Whether the first sync has delivered the store (ios.md §11).
    public var setupComplete: Bool {
        get { defaults.bool(forKey: Key.setupComplete) }
        nonmutating set { defaults.set(newValue, forKey: Key.setupComplete) }
    }

    /// When the app last flushed the collection file (ios.md §9.6).
    public var lastFlushAt: Date? {
        get { defaults.object(forKey: Key.lastFlushAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastFlushAt) }
    }

    /// The app wrote the running entry: record the store's `LiveState` (it
    /// already merges what sync applied) and the time, so providers reuse it
    /// for 5 seconds instead of fetching.
    public func recordAppWrite(_ state: LiveState, at now: Date) {
        liveState = state
        lastAppWriteAt = now
    }
}

extension Data {
    /// The bytes as lowercase hex, the form APNs device tokens are sent in.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
