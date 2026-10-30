// LivePresenceProbe: idle time, lock, console owner, and display state from
// Core Graphics (spec_activity_tracking.md §3.4; no permission needed).

import CoreGraphics

/// Reads `CGEventSource` idle seconds, the `CGSession` dictionary, and the
/// main display's sleep state.
struct LivePresenceProbe: PresenceProbe {
    func read() -> PresenceReading {
        let anyInput = CGEventType(rawValue: UInt32.max) ?? .null
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let session = (CGSessionCopyCurrentDictionary() as? [String: Any]) ?? [:]
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool ?? true
        let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        return PresenceReading(idleSeconds: idle, displayAsleep: asleep, locked: locked, otherUserOnConsole: !onConsole)
    }
}
