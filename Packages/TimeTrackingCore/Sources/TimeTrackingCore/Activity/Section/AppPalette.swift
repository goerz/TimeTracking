// AppPalette: the fixed app color sequence of the Activity section
// (activity.md §1.3).

/// The fixed, synced app color sequence (§1.3).
public enum AppPalette {
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

    /// `colors` with an index for every app of `apps` that has none: the
    /// least-used index, lowest on ties, in the given order. Existing
    /// assignments never change.
    public static func assigning(_ apps: [String], to colors: [String: Int]) -> [String: Int] {
        var result = colors
        for app in apps where result[app] == nil {
            result[app] = SettingMerge.hueIndex(forNewAppIn: result, hueCount: count)
        }
        return result
    }
}
