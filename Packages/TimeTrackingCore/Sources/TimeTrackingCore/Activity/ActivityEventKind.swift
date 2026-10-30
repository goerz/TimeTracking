// ActivityEventKind: the kinds of the "Log activity event" intent
// (spec_ios.md §6.1, §9.4).

/// What a Shortcuts automation reports; the raw value is the `kind` of the
/// `intent` line.
public enum ActivityEventKind: String, Sendable, Hashable, CaseIterable {
    case appOpened
    case appClosed
    case arrived
    case left
    case chargerConnected
    case chargerDisconnected
    case custom

    /// The name Shortcuts shows.
    public var title: String {
        switch self {
        case .appOpened: "App Opened"
        case .appClosed: "App Closed"
        case .arrived: "Arrived"
        case .left: "Left"
        case .chargerConnected: "Charger Connected"
        case .chargerDisconnected: "Charger Disconnected"
        case .custom: "Custom"
        }
    }
}
