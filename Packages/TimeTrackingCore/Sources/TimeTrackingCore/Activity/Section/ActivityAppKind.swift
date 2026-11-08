// ActivityAppKind: what kind of app an item's app is (activity.md §1.3).

/// The kinds of the app chips' glyph table.
public enum ActivityAppKind: String, Sendable, Hashable {
    case terminal
    /// Every browser shares one glyph.
    case browser
    /// An iOS Screen Time set; its glyph is the device's.
    case screenTime
    case other

    /// Bundle identifiers of the terminals the tracker reads.
    public static let terminalIDs: Set<String> = ["com.github.wez.wezterm", "com.googlecode.iterm2", "com.apple.Terminal"]
    /// Bundle identifiers of the browsers, the iOS web extension's included.
    public static let browserIDs: Set<String> = [
        "com.apple.Safari", "com.apple.mobilesafari", "com.google.Chrome", "company.thebrowser.Browser",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "org.mozilla.firefox",
    ]

    /// The kind of an Item's app, from its appID.
    public init(item: ActivityItem) {
        if item.isScreenTime {
            self = .screenTime
        } else if Self.browserIDs.contains(item.appID) {
            self = .browser
        } else if Self.terminalIDs.contains(item.appID) {
            self = .terminal
        } else {
            self = .other
        }
    }
}
