// SettingMerge: the field-level merge of synced settings (spec_data_and_sync.md §1.6).

/// The names of synced settings with a field-level merge.
public enum SettingMerge {
    /// The key of `activity.contextColors`.
    public static let contextColorsKey = SyncedSettingKey<[String: Int]>.activityContextColors.name

    /// The union of two context color maps; the smaller index wins for a
    /// context assigned differently.
    public static func mergeContextColors(_ lhs: [String: Int], _ rhs: [String: Int]) -> [String: Int] {
        lhs.merging(rhs) { min($0, $1) }
    }

    /// The hue index for a new context: the one used by the fewest
    /// contexts, the lowest on ties.
    public static func hueIndex(forNewContextIn colors: [String: Int], hueCount: Int) -> Int {
        var counts = Array(repeating: 0, count: max(hueCount, 1))
        for index in colors.values where counts.indices.contains(index) {
            counts[index] += 1
        }
        let fewest = counts.min() ?? 0
        return counts.firstIndex(of: fewest) ?? 0
    }
}
