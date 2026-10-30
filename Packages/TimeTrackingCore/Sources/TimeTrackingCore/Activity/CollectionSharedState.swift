// CollectionSharedState: what the iOS app and its collectors share in the
// App Group about the activity collection (spec_ios.md §2.9, §9, §11).

public import Foundation

/// The ladder's configuration and per-set ledgers, as the app writes them
/// and the monitor extension reads and updates them.
public protocol LadderStore: Sendable {
    /// The sets, "Everything" first.
    var ladderSets: [LadderSet] { get }
    /// The measured event cap, `nil` before the measurement.
    var eventCap: Int? { get }

    func ladderState(for setID: String) -> LadderSetState?
    func setLadderState(_ state: LadderSetState?, for setID: String)
}

/// Values in the App Group's `UserDefaults` suite, read and written by the
/// app and the App Intents, monitor, and Safari extensions.
public struct CollectionSharedState: LadderStore, @unchecked Sendable {
    /// UserDefaults is thread-safe.
    private let defaults: UserDefaults

    private enum Key {
        static let enabled = "collection.enabled"
        static let focusLabel = "collection.focus.label"
        static let focusSuspends = "collection.focus.suspends"
        static let lastWebEventAt = "collection.lastWebEventAt"
        static let lastFocusEventAt = "collection.lastFocusEventAt"
        static let lastIntentEventAt = "collection.lastIntentEventAt"
        static let sets = "collection.ladder.sets"
        static let eventCap = "collection.ladder.eventCap"
        static let statePrefix = "collection.ladder.state."
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The App Group suite of `identity`, or the standard defaults.
    public init(identity: AppIdentity?) {
        self.defaults = identity.flatMap { UserDefaults(suiteName: $0.appGroup) } ?? .standard
    }

    /// The master switch of the Activity collection screen (off by default).
    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// The label of the Focus whose `on` was logged last, until its `off`.
    public var focusLabel: String? {
        get { defaults.string(forKey: Key.focusLabel) }
        nonmutating set { defaults.set(newValue, forKey: Key.focusLabel) }
    }

    /// Whether the Focus that is on suspends the Safari and automation collectors.
    public var focusSuspendsCollection: Bool {
        get { defaults.bool(forKey: Key.focusSuspends) }
        nonmutating set { defaults.set(newValue, forKey: Key.focusSuspends) }
    }

    /// When the Safari extension last delivered a message (onboarding check mark).
    public var lastWebEventAt: Date? {
        get { defaults.object(forKey: Key.lastWebEventAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastWebEventAt) }
    }

    /// When the Focus filter last ran (onboarding check mark).
    public var lastFocusEventAt: Date? {
        get { defaults.object(forKey: Key.lastFocusEventAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastFocusEventAt) }
    }

    /// When an automation last logged an event (onboarding check mark).
    public var lastIntentEventAt: Date? {
        get { defaults.object(forKey: Key.lastIntentEventAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastIntentEventAt) }
    }

    /// The app sets, "Everything" always first and always present.
    public var ladderSets: [LadderSet] {
        get {
            let stored = defaults.data(forKey: Key.sets).flatMap { try? JSONDecoder().decode([LadderSet].self, from: $0) } ?? []
            return [stored.first(where: \.isEverything) ?? .everything] + stored.filter { !$0.isEverything }
        }
        nonmutating set {
            var sets = newValue.filter { !$0.isEverything }
            sets.insert(newValue.first(where: \.isEverything) ?? .everything, at: 0)
            defaults.set(try? JSONEncoder().encode(sets), forKey: Key.sets)
        }
    }

    public var eventCap: Int? {
        get { defaults.object(forKey: Key.eventCap) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Key.eventCap) }
    }

    public func ladderState(for setID: String) -> LadderSetState? {
        defaults.data(forKey: Key.statePrefix + setID).flatMap { try? JSONDecoder().decode(LadderSetState.self, from: $0) }
    }

    public func setLadderState(_ state: LadderSetState?, for setID: String) {
        guard let state else {
            defaults.removeObject(forKey: Key.statePrefix + setID)
            return
        }
        defaults.set(try? JSONEncoder().encode(state), forKey: Key.statePrefix + setID)
    }
}
