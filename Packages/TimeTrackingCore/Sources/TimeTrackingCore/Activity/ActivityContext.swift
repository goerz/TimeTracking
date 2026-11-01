// ActivityContext: context kinds, display names, and the context color
// sequence of the Activity section (spec_activity.md §1.2, §1.3).

/// What kind of place a context is.
public enum ActivityContextKind: String, Sendable, Hashable {
    /// A terminal session, `tmux:<name>`.
    case session
    /// A browser (`safari`, `chrome`, …).
    case browser
    /// Any other app.
    case app
}

/// A context as the Activity section and the Calendar show it.
public struct ActivityContext: Sendable, Hashable {
    /// The context string of the log, e.g. `tmux:paper`.
    public var name: String

    public init(_ name: String) {
        self.name = name
    }

    /// The browsers with their display names.
    public static let browsers: [String: String] = [
        "safari": "Safari", "arc": "Arc", "chrome": "Chrome", "brave": "Brave", "edge": "Edge", "vivaldi": "Vivaldi",
        "firefox": "Firefox",
    ]

    public var kind: ActivityContextKind {
        if name.hasPrefix("tmux:") {
            return .session
        }
        return Self.browsers[name] == nil ? .app : .browser
    }

    /// `tmux:(private)` and other contexts written as `(private)`: gray, no color index.
    public var isPrivate: Bool {
        name.hasSuffix("(private)")
    }

    /// The display name; `appName` maps a bundle identifier to an app name
    /// (the app layer knows installed apps, the library does not).
    public func displayName(bundleIdentifier: String? = nil, appName: (String) -> String? = { _ in nil }) -> String {
        switch kind {
        case .session:
            return isPrivate ? "(private session)" : String(name.dropFirst("tmux:".count))
        case .browser:
            return Self.browsers[name] ?? name
        case .app:
            if let bundleIdentifier, let app = appName(bundleIdentifier) {
                return app
            }
            return Self.appDisplayName(name)
        }
    }

    /// The bare domain of a site subject (`github.com/owner/repo` → `github.com`).
    public static func domain(ofSite subject: String) -> String {
        String(subject.split(separator: "/", maxSplits: 1).first ?? Substring(subject))
    }
}

/// The fixed, synced context color sequence (§1.3).
public enum ContextPalette {
    /// Light and dark hex colors by index.
    public static let colors: [(light: String, dark: String)] = [
        ("#3B5BDB", "#5C7CFA"), ("#9A6B1E", "#D9A441"), ("#2B8A3E", "#51CF66"), ("#7048E8", "#9775FA"),
        ("#E8590C", "#FF922B"), ("#1864AB", "#4DABF7"), ("#C2255C", "#F06595"), ("#5F3DC4", "#845EF7"),
        ("#0B7285", "#22B8CF"), ("#862E9C", "#CC5DE8"), ("#087F5B", "#38D9A9"), ("#A61E4D", "#E64980"),
    ]

    public static var count: Int {
        colors.count
    }

    /// The hex color of `index` (wrapping), or `nil` for no index (gray).
    public static func hex(_ index: Int?, dark: Bool) -> String? {
        guard let index else {
            return nil
        }
        let pair = colors[((index % count) + count) % count]
        return dark ? pair.dark : pair.light
    }

    /// `colors` with an index for every context of `contexts` that has
    /// none: the least-used index, lowest on ties, in the given order.
    /// Private contexts take none. Existing assignments never change.
    public static func assigning(_ contexts: [String], to colors: [String: Int]) -> [String: Int] {
        var result = colors
        for context in contexts where result[context] == nil && !ActivityContext(context).isPrivate {
            result[context] = SettingMerge.hueIndex(forNewContextIn: result, hueCount: count)
        }
        return result
    }
}
