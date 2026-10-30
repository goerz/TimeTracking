// AppResolver: items of documents, Finder, chat and meeting apps, and every
// other app (spec_activity_tracking.md §2.2, §2.4 step 3, §7.2).

import Foundation
import TimeTrackingCore

/// Resolves apps that are neither terminals nor browsers.
///
/// Document apps give `AXDocument` (subject the work folder, detail the
/// file name), else the title; Finder gives its front window's folder; chat
/// apps give workspace and channel from the title; meeting and
/// screen-sharing apps give the meeting or host from the title; any other
/// app gives its name plus the window title.
@MainActor
struct AppResolver {
    nonisolated static let finderScript = """
    with timeout of 1 seconds
        tell application id "com.apple.finder" to return POSIX path of (target of front Finder window as alias)
    end timeout
    """

    /// Chat apps whose titles carry workspace and channel.
    nonisolated static let chatApps: Set = [
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.mattermost.desktop", "com.apple.MobileSMS",
        "org.whispersystems.signal-desktop", "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp",
    ]

    /// Context names of well-known apps; others use their lowercased name.
    nonisolated static let contextNames: [String: String] = [
        "com.apple.mail": "mail",
        "com.apple.finder": "finder",
        "com.apple.Preview": "preview",
        "net.sourceforge.skim-app.skim": "skim",
        "com.microsoft.VSCode": "vscode",
        "com.apple.dt.Xcode": "xcode",
        "com.tinyspeck.slackmacgap": "slack",
        "us.zoom.xos": "zoom",
        "com.microsoft.teams2": "teams",
        "com.apple.iWork.Pages": "pages",
        "com.apple.iWork.Keynote": "keynote",
        "com.apple.iWork.Numbers": "numbers",
        "com.microsoft.Word": "word",
        "com.microsoft.Excel": "excel",
        "com.microsoft.Powerpoint": "powerpoint",
    ]

    let environment: AgentEnvironment

    static func contextName(_ app: FrontApp) -> String {
        contextNames[app.bundleID] ?? app.name.lowercased()
    }

    func resolve(app: FrontApp, window: WindowInfo?, context: inout ResolveContext) -> SampleItem {
        let name = Self.contextName(app)
        let title = context.filteredTitle(window?.title ?? "")
        let plain = SampleItem(context: name, subject: title, groupKey: name, app: app.bundleID)
        if app.bundleID == "com.apple.finder" {
            if case let .value(folder) = environment.scripts.run(Self.finderScript), !folder.isEmpty {
                let path = ResolveContext.plainPath(folder)
                let item = SampleItem(context: name, subject: context.tilde(path), groupKey: context.workFolder(ofFolder: path), app: app.bundleID)
                return context.exclusions.excludesPath(path) ? ResolveContext.privatePath(item) : item
            }
            return plain
        }
        if let document = window?.document, !document.isEmpty {
            let path = ResolveContext.plainPath(document)
            let folder = context.workFolder(ofFile: path)
            let item = SampleItem(context: name, subject: folder, detail: (path as NSString).lastPathComponent, groupKey: folder, app: app.bundleID)
            return context.exclusions.excludesPath(path) ? ResolveContext.privatePath(item) : item
        }
        if Self.chatApps.contains(app.bundleID), let parsed = Self.chatTitle(title, appName: app.name) {
            return SampleItem(context: name, subject: parsed.workspace, detail: parsed.channel, groupKey: name, app: app.bundleID)
        }
        return plain
    }

    /// Workspace and channel of titles such as `general (Channel) - Acme - Slack`
    /// or `#general | Acme - Discord`.
    static func chatTitle(_ title: String, appName: String) -> (workspace: String, channel: String)? {
        var parts = title.components(separatedBy: " - ").flatMap { $0.components(separatedBy: " | ") }.map {
            $0.trimmingCharacters(in: .whitespaces)
        }
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
