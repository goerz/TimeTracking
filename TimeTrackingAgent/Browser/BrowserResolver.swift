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
    var health: [SourceReport]
}

/// Reads the active tab through Apple Events (Safari; Chromium browsers
/// with their incognito flag), else `AXURL` plus title with "Private
/// Browsing" in the title marking a private window. A Safari URL with no
/// visit in a copy of `History.db` is a private window's: the item becomes
/// `safari (private)` and the URL is never recorded. Without Full Disk
/// Access, Safari URLs keep only the domain.
@MainActor
final class BrowserResolver {
    /// How far back a `History.db` visit proves that a tab is not private.
    static let visitLookback: TimeInterval = 86_400

    private let environment: AgentEnvironment
    private var verified: [String: Date] = [:]

    init(environment: AgentEnvironment) {
        self.environment = environment
    }

    /// The active tab as the browser reported it.
    private struct Tab {
        var mode = "normal"
        var url: String?
        var title: String
        var health: [SourceReport] = []

        var isPrivate: Bool {
            mode.lowercased() == "incognito" || title.contains("Private Browsing")
        }
    }

    func resolve(app: FrontApp, window: WindowInfo?, ports: PortRegistry, context: inout ResolveContext) -> BrowserObservation {
        let browser = BrowserApp.known[app.bundleID] ?? BrowserApp(context: app.name.lowercased(), scripting: .unscriptable)
        let tab = readTab(app: app, browser: browser, window: window)
        let hidden = BrowserObservation(item: Self.privateItem(browser, app), url: "", title: "", domain: nil, health: tab.health)
        if tab.isPrivate {
            return hidden
        }
        let title = context.filteredTitle(tab.title)
        let plain = BrowserObservation(
            item: SampleItem(context: browser.context, subject: title, groupKey: browser.context, app: app.bundleID),
            url: "",
            title: title,
            domain: nil,
            health: tab.health
        )
        guard let url = tab.url, !url.isEmpty else {
            return plain
        }
        if url.lowercased().hasPrefix("file://") {
            var observation = plain
            observation.item = fileItem(url, browser: browser, app: app, context: &context)
            return observation
        }
        let rules = BrowserItemRules(settings: context.settings.browser, exclusions: context.exclusions)
        guard let parts = rules.parts(for: url) else {
            return plain
        }
        if parts.isExcluded {
            return hidden
        }
        if let port = Self.localPort(parts.domain), let paneItem = ports.item(forPort: port) {
            return BrowserObservation(item: paneItem, url: parts.loggedURL ?? "", title: title, domain: parts.domain, health: tab.health)
        }
        var observation = webObservation(parts, tab: Tab(url: url, title: title), browser: browser, app: app, context: context)
        observation.health = tab.health + observation.health
        return observation
    }

    /// Apple Events where the browser has a dictionary and allows them, else the window's `AXURL`.
    private func readTab(app: FrontApp, browser: BrowserApp, window: WindowInfo?) -> Tab {
        var tab = Tab(url: window?.url, title: window?.title ?? "")
        guard let script = browser.script(bundleID: app.bundleID) else {
            tab.health.append(SourceReport("browser", .fallback, "\(app.name) has no scripting dictionary; using the window's URL"))
            return tab
        }
        switch environment.scripts.run(script) {
        case let .value(text):
            let lines = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 2 {
                tab.mode = lines[0]
                tab.url = lines[1]
                tab.title = lines.count > 2 ? lines[2] : tab.title
            }
            tab.health.append(SourceReport("browser", .active))
        case .denied:
            tab.health.append(SourceReport("browser", .fallback, "Automation not granted for \(app.name)"))
        case .failed:
            break
        }
        return tab
    }

    /// A `file://` tab is a document: work folder and file name.
    private func fileItem(_ url: String, browser: BrowserApp, app: FrontApp, context: inout ResolveContext) -> SampleItem {
        let path = ResolveContext.plainPath(url)
        let folder = context.workFolder(ofFile: path)
        let item = SampleItem(
            context: browser.context,
            subject: folder,
            detail: PathText.lastComponent(path),
            groupKey: folder,
            app: app.bundleID
        )
        return context.exclusions.excludesPath(path) ? ResolveContext.privatePath(item) : item
    }

    /// A web tab; Safari tabs need Full Disk Access for more than the domain
    /// and a `History.db` visit to be recorded at all.
    private func webObservation(
        _ parts: BrowserItemRules.Parts,
        tab: Tab,
        browser: BrowserApp,
        app: FrontApp,
        context: ResolveContext
    ) -> BrowserObservation {
        var health: [SourceReport] = []
        let url = tab.url ?? ""
        let title = tab.title
        var item = SampleItem(
            context: browser.context,
            subject: parts.subject,
            detail: parts.detail,
            groupKey: parts.groupKey,
            app: app.bundleID
        )
        var loggedURL = parts.loggedURL ?? ""
        // A private domain keeps only its domain, so not its page titles either.
        let keptTitle = context.exclusions.isPrivateDomain(url) ? "" : title
        if browser.scripting == .safari {
            if !environment.history.canReadSafari {
                item.subject = parts.domain
                item.detail = ""
                item.groupKey = parts.domain
                loggedURL = ""
                health.append(SourceReport("history", .fallback, "Full Disk Access not granted; Safari URLs keep only the domain"))
            } else if !isVerified(url, now: environment.clock.now) {
                return BrowserObservation(item: Self.privateItem(browser, app), url: "", title: "", domain: nil, health: health)
            }
        }
        return BrowserObservation(item: item, url: loggedURL, title: keptTitle, domain: parts.domain, health: health)
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
