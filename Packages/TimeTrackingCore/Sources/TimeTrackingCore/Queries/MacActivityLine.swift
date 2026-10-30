// MacActivityLine: the Mac activity line under the Timer card and in the
// medium widget's footer (spec_ios.md §2.3).

public import Foundation

/// The Mac activity line under the Timer card and in the medium widget's
/// footer (spec_ios.md §2.3).
public enum MacActivityLine {
    /// One line per Mac whose tracker runs, most recently updated first, at
    /// most two: "MacBook · tmux:paper draft · active".
    public static func lines(_ state: LiveState, timeZone: TimeZone, limit: Int = 2) -> [String] {
        state.activity.values
            .filter(\.agentRunning)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { line($0, timeZone: timeZone) }
    }

    static func line(_ activity: LiveState.MacActivity, timeZone: TimeZone) -> String {
        var parts = [activity.device]
        if let item = item(activity.primary) {
            parts.append(item)
        }
        if let presence = presence(activity, timeZone: timeZone) {
            parts.append(presence)
        }
        return parts.joined(separator: " · ")
    }

    /// The context and subject; the subject alone when the context is a
    /// plain app name (no `kind:name` form).
    static func item(_ primary: TrackerPrimaryItem?) -> String? {
        guard let primary else {
            return nil
        }
        if primary.subject.isEmpty {
            return primary.context.isEmpty ? nil : primary.context
        }
        if primary.context.contains(":") {
            return "\(primary.context) \(primary.subject)"
        }
        return primary.subject
    }

    /// "active", "passive", "idle since 14:02", "locked since 14:02", "asleep since 14:02".
    static func presence(_ activity: LiveState.MacActivity, timeZone: TimeZone) -> String? {
        guard let presence = activity.presence, !presence.isEmpty else {
            return nil
        }
        guard ["idle", "locked", "asleep"].contains(presence), let since = activity.since else {
            return presence
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "\(presence) since \(formatter.string(from: since))"
    }
}
