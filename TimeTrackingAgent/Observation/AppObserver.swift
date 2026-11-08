// AppObserver: the Item of a frontmost app that is neither a terminal nor a
// browser: documents, Finder, chat apps, any other app
// (activity_tracking.md §2.3).

import Foundation
import TimeTrackingCore

/// Document apps give their document (`AXDocument`) and its folder, Finder
/// its front window's folder, chat apps their workspace as the session,
/// and every app its window title.
@MainActor
struct AppObserver {
    static let finderScript = """
    with timeout of 1 seconds
        tell application id "com.apple.finder" to return POSIX path of (target of front Finder window as alias)
    end timeout
    """
    /// Chat apps whose titles carry workspace and channel.
    static let chatApps: Set = [
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.mattermost.desktop", "com.apple.MobileSMS",
        "org.whispersystems.signal-desktop", "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp",
    ]

    let environment: AgentEnvironment

    func observe(app: FrontApp, window: WindowInfo?) -> ActivityItem {
        let paths = HomePaths(home: environment.homeDirectory)
        let title = window?.title ?? ""
        var item = ActivityItem(app: app.name, appID: app.bundleID, window: title)
        if app.bundleID == "com.apple.finder" {
            if case let .value(folder) = environment.scripts.run(Self.finderScript), !folder.isEmpty {
                item.location = paths.tilde(folder)
            }
            return item
        }
        if let document = window?.document, !document.isEmpty {
            return paths.withDocument(document, in: item)
        }
        if Self.chatApps.contains(app.bundleID), let parsed = Self.chatTitle(title, appName: app.name) {
            item.window = parsed.channel
            item.session = parsed.workspace
        }
        return item
    }

    /// Workspace and channel of titles such as `general (Channel) - Acme - Slack`
    /// or `#general | Acme - Discord`.
    static func chatTitle(_ title: String, appName: String) -> (workspace: String, channel: String)? {
        var parts = title.components(separatedBy: " - ").flatMap { $0.components(separatedBy: " | ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.last?.caseInsensitiveCompare(appName) == .orderedSame {
            parts.removeLast()
        }
        if parts.first?.caseInsensitiveCompare(appName) == .orderedSame {
            parts.removeFirst()
        }
        guard parts.count >= 2 else {
            return nil
        }
        var channel = parts[0]
        if let open = channel.range(of: " (", options: .backwards), channel.hasSuffix(")") {
            channel = String(channel[..<open.lowerBound])
        }
        return (parts[parts.count - 1], channel)
    }
}
