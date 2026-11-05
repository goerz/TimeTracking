// ActivityText: the duration and clock texts of the Activity section
// (activity.md §1.2).

/// Duration texts of the Activity section (§1.2).
public enum ActivityText {
    /// `Nh MMm` from one hour (`Nh` on the hour), `Mm` below, `Ss` below one
    /// minute; zero reads `0h`, as in the day totals.
    public static func duration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds == 0 {
            return "0h"
        }
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest < 10 ? "0" : "")\(rest)m"
    }

    /// "09:00".
    public static func clock(hour: Int, minute: Int = 0) -> String {
        "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
    }
}
