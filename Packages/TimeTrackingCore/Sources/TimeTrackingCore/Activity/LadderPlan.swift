// LadderPlan: the thresholds of the DeviceActivity ladder, how the event cap
// is divided among the sets, and the cap measurement (spec_ios.md §9.2,
// spec_activity_tracking.md §6.2 and phase 7).

/// The threshold steps (minutes of daily use) each set registers.
///
/// "Everything" climbs in 1-minute steps to 60 and then in 5-minute steps;
/// a named set in 1-minute steps to 10 and then in 5-minute steps. The cap
/// on registered events is divided among the sets by expected use: named
/// sets together get 16 % of it (at least 10 each, at most half the cap),
/// and "Everything" the rest. With a cap of 100 and one named set that is
/// "Everything" 1 to 60 and 65 to 180, the named set 1 to 10 and 15 to 40.
/// A set registers one window of its budget's size at a time; at the
/// window's last step the next window follows.
public enum LadderPlan {
    /// The cap assumed until the first run measured one.
    public static let defaultCap = 100
    /// The counts the measurement tries, ascending.
    public static let probeCounts = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]
    /// No step goes beyond a whole day.
    public static let lastMinute = 1440

    /// The `index`-th threshold (0-based) of a set's ladder, in minutes.
    public static func threshold(at index: Int, everything: Bool) -> Int {
        let fine = everything ? 60 : 10
        let minutes = index < fine ? index + 1 : fine + 5 * (index - fine + 1)
        return min(minutes, lastMinute)
    }

    /// The events each set may register, by set id.
    public static func budgets(cap: Int, sets: [LadderSet]) -> [String: Int] {
        let named = sets.filter { !$0.isEverything }
        guard !named.isEmpty else {
            return Dictionary(uniqueKeysWithValues: sets.map { ($0.id, cap) })
        }
        let namedTotal = min(cap / 2, max(cap * 16 / 100, 10 * named.count))
        let each = max(1, namedTotal / named.count)
        var result: [String: Int] = [:]
        for set in named {
            result[set.id] = each
        }
        if sets.contains(where: \.isEverything) {
            result[LadderSet.everythingID] = max(1, cap - each * named.count)
        }
        return result
    }

    /// The next window: up to `budget` thresholds above `step` (all from
    /// the first when `nil`).
    public static func window(after step: Int?, budget: Int, everything: Bool) -> [Int] {
        var result: [Int] = []
        var index = 0
        while result.count < budget {
            let minutes = threshold(at: index, everything: everything)
            if minutes > (step ?? 0), result.last != minutes {
                result.append(minutes)
            }
            if minutes >= lastMinute {
                break
            }
            index += 1
        }
        return result
    }

    /// The event cap: registers 1, 2, 4, …, 512 events through `register`
    /// and returns the largest count it accepted (0 when none was).
    public static func measureCap(register: (Int) throws -> Void) -> Int {
        var accepted = 0
        for count in probeCounts {
            do {
                try register(count)
                accepted = count
            } catch {
                break
            }
        }
        return accepted
    }
}
