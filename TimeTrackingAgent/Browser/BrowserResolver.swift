// BrowserResolver: the item of a frontmost browser's active tab, with the
// private-window test (spec_activity_tracking.md §2.2 rule 2 and 4, §3.3, §7.2).

import Foundation
import TimeTrackingCore

/// What a browser gives: the item, the URL the logs may keep, the title,
/// and the tab's domain (for passive domains).
struct BrowserObservation {
    var item: SampleItem
    var url: String
    var title: String
    var domain: String?
    var health: [(id: String, status: TrackerSourceStatus, reason: String)]
}

/// Reads the active tab through Apple Events (Safari; Chromium browsers
/// with their incognito flag), else `AXURL` plus title with "Private
/// Browsing" in the title marking a private window. A Safari URL with no
/// visit in a copy of `History.db` is a private window's: the item becomes
/// `safari (private)` and the URL is dropped. Without Full Disk Access,
/// Safari URLs keep only the domain.
@MainActor
final class BrowserResolver {
    /// How far back a `History.db` visit proves that a tab is not private.
    static let visitLookback: TimeInterval = 86400
    /// How long a Safari URL may wait for its visit to be written (§3.3).
    static let privateTestWindow: TimeInterval = 180

    private let environment: AgentEnvironment
    private var verified: [String: Date] = [:]

    init(environment: AgentEnvironment) {
        self.environment = environment
    }

    func resolve(app: FrontApp, window: WindowInfo?, ports: PortRegistry, context: inout ResolveContext) -> BrowserObservation {
        let browser = BrowserApp.known[app.bundleID] ?? BrowserApp(context: app.name.lowercased(), scripting: .none)
        var health: [(String, TrackerSourceStatus, String)] = []
        var mode = "normal"
        var url = window?.url
        var title = window?.title ?? ""
        if let script = browser.script(bundleID: app.bundleID) {
            switch environment.scripts.run(script) {
            case let .value(text):
                let lines = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                if lines.count >= 2 {
                    mode = lines[0]
                    url = lines[1]
                    title = lines.count > 2 ? lines[2] : title
                }
                health.append(("browser", .active, ""))
            case .denied:
                health.append(("browser", .fallback, "Automation not granted for \(app.name)"))
            case .failed:
                break
            }
        } else {
            health.append(("browser", .fallback, "\(app.name) has no scripting dictionary; using the window's URL"))
        }
        let privateWindow = mode.lowercased() == "incognito" || title.contains("Private Browsing")
        if privateWindow {
            return BrowserObservation(item: Self.privateItem(browser, app), url: "", title: "", domain: nil, health: health)
        }
        let filteredTitle = context.filteredTitle(title)
        guard let url, !url.isEmpty else {
            let item = SampleItem(context: browser.context, subject: filteredTitle, groupKey: browser.context, app: app.bundleID)
            return BrowserObservation(item: item, url: "", title: filteredTitle, domain: nil, health: health)
        }
        if url.lowercased().hasPrefix("file://") {
            let path = ResolveContext.plainPath(url)
            var item = SampleItem(
                context: browser.context,
                subject: context.workFolder(ofFile: path),
                detail: (path as NSString).lastPathComponent,
                groupKey: context.workFolder(ofFile: path),
                app: app.bundleID
            )
            if context.exclusions.excludesPath(path) {
                item = ResolveContext.privatePath(item)
            }
            return BrowserObservation(item: item, url: "", title: filteredTitle, domain: nil, health: health)
        }
        let rules = BrowserItemRules(settings: context.settings.browser, exclusions: context.exclusions)
        guard let parts = rules.parts(for: url) else {
            let item = SampleItem(context: browser.context, subject: filteredTitle, groupKey: browser.context, app: app.bundleID)
            return BrowserObservation(item: item, url: "", title: filteredTitle, domain: nil, health: health)
        }
        if parts.isExcluded {
            return BrowserObservation(item: Self.privateItem(browser, app), url: "", title: "", domain: parts.domain, health: health)
        }
        if let port = Self.localPort(parts.domain), let paneItem = ports.item(forPort: port) {
            return BrowserObservation(item: paneItem, url: parts.loggedURL ?? "", title: filteredTitle, domain: parts.domain, health: health)
        }
        var item = SampleItem(context: browser.context, subject: parts.subject, detail: parts.detail, groupKey: parts.groupKey, app: app.bundleID)
        var loggedURL = parts.loggedURL ?? ""
        if browser.scripting == .safari {
            let now = environment.clock.now
            if !environment.history.canReadSafari {
                item.subject = parts.domain
                item.detail = ""
                item.groupKey = parts.domain
                loggedURL = ""
                health.append(("history", .fallback, "Full Disk Access not granted; Safari URLs keep only the domain"))
            } else if !isVerified(url, now: now) {
                return BrowserObservation(item: Self.privateItem(browser, app), url: "", title: "", domain: nil, health: health)
            }
        }
        return BrowserObservation(item: item, url: loggedURL, title: filteredTitle, domain: parts.domain, health: health)
    }

    /// Whether Safari's history has a visit of `url`; a verified URL stays
    /// verified for the lookback.
    private func isVerified(_ url: String, now: Date) -> Bool {
        if let time = verified[url], now.timeIntervalSince(time) < Self.visitLookback {
            return true
        }
        guard environment.history.hasSafariVisit(url: url, since: now.addingTimeInterval(-Self.visitLookback)) == true else {
            return false
        }
        if verified.count > 1000 {
            verified.removeAll()
        }
        verified[url] = now
        return true
    }

    /// `<browser> (private)`: no URL, no title.
    static func privateItem(_ browser: BrowserApp, _ app: FrontApp) -> SampleItem {
        SampleItem(context: browser.context, subject: ExclusionRules.privateMarker, groupKey: browser.context, app: app.bundleID)
    }

    /// The port of `localhost:<port>` or `127.0.0.1:<port>`.
    static func localPort(_ domain: String) -> Int? {
        let parts = domain.split(separator: ":")
        guard parts.count == 2, ["localhost", "127.0.0.1", "[::1]"].contains(parts[0].lowercased()) else {
            return nil
        }
        return Int(parts[1])
    }
}
