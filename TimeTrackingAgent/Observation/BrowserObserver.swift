// BrowserObserver: the Item of a frontmost browser's active tab, with the
// private-window test (activity_tracking.md §2.3, §3.3, §7.2).

import Foundation
import TimeTrackingCore

/// Reads the active tab through Apple Events (Safari; Chromium browsers with
/// their incognito flag), else `AXURL` plus title, with "Private Browsing"
/// in the title marking a private window. A Safari URL with no visit in the
/// last 24 hours of `History.db` is a private window's. Without Full Disk
/// Access, Safari URLs keep only their domain.
@MainActor
final class BrowserObserver {
    /// How far back a `History.db` visit proves that a tab is not private.
    static let visitLookback: TimeInterval = 86_400

    private let environment: AgentEnvironment
    private let paths: HomePaths
    private var verified: [String: Date] = [:]

    init(environment: AgentEnvironment) {
        self.environment = environment
        self.paths = HomePaths(home: environment.homeDirectory)
    }

    /// The tab as the browser reported it.
    private struct Tab {
        var mode = "normal"
        var url: String?
        var title: String
        var health: [SourceReport] = []

        var isPrivate: Bool {
            mode.lowercased() == "incognito" || title.contains("Private Browsing")
        }
    }

    func observe(app: FrontApp, window: WindowInfo?, exclusions: ExclusionRules) -> FrontObservation {
        let browser = BrowserApp.known[app.bundleID] ?? BrowserApp(scripting: .unscriptable)
        let tab = readTab(app: app, browser: browser, window: window)
        var observation = FrontObservation(bundleID: app.bundleID, health: tab.health)
        let hidden = ActivityItem(app: app.name, appID: app.bundleID, location: Redactor.marker)
        let plain = ActivityItem(app: app.name, appID: app.bundleID, window: tab.title)
        guard !tab.isPrivate else {
            observation.item = hidden
            return observation
        }
        guard let url = tab.url, !url.isEmpty else {
            observation.item = plain
            return observation
        }
        if url.lowercased().hasPrefix("file://") {
            observation.item = paths.withDocument(url, in: ActivityItem(app: app.name, appID: app.bundleID, window: tab.title))
            return observation
        }
        guard let host = URL(string: url)?.host()?.lowercased() else {
            observation.item = plain
            return observation
        }
        observation.domain = host
        if exclusions.excludesDomain(host) {
            observation.item = hidden
            return observation
        }
        // An excluded domain was hidden above; a private one is reduced as the Sample is written.
        var item = ActivityItem(app: app.name, appID: app.bundleID, window: tab.title, location: url)
        if browser.scripting == .safari {
            let verified = environment.history.canReadSafari ? isVerified(url, now: environment.clock.now) : nil
            switch verified {
            case nil:
                // History can't be read: the domain only, never taken for a private window.
                item.location = (URL(string: url)?.scheme ?? "https") + "://" + host
                let reason = environment.history.canReadSafari ? "Safari's history can't be read; Safari addresses keep their domain only"
                    : SourceID.noFullDiskAccessReason
                observation.health.append(SourceReport(.history, .fallback, reason))
            case false?:
                item = hidden
            case true?:
                break
            }
        }
        observation.item = item
        return observation
    }

    /// Apple Events where the browser has a dictionary and allows them, else the window's `AXURL`.
    private func readTab(app: FrontApp, browser: BrowserApp, window: WindowInfo?) -> Tab {
        var tab = Tab(url: window?.url, title: window?.title ?? "")
        guard let script = browser.script(bundleID: app.bundleID) else {
            tab.health.append(SourceReport(.browser, .fallback, "\(app.name) can't report its tab; the address is read from the window"))
            return tab
        }
        switch environment.scripts.run(script) {
        case let .value(text):
            let lines = text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 2 {
                tab.mode = lines[0]
                tab.url = lines[1]
                tab.title = lines.count > 2 ? lines[2].trimmingCharacters(in: .newlines) : tab.title
            }
            tab.health.append(SourceReport(.browser, .active))
        case .denied:
            tab.health.append(SourceReport(.browser, .fallback, "Automation is off for \(app.name); the address is read from the window"))
        case .failed:
            break
        }
        return tab
    }

    /// Whether Safari's history has a visit of `url`, `nil` when it can't
    /// be read; a verified URL stays verified for the lookback.
    private func isVerified(_ url: String, now: Date) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        if let time = verified[url], now.timeIntervalSince(time) < Self.visitLookback {
            return true
        }
        guard let visited = environment.history.hasSafariVisit(url: url, since: now - Self.visitLookback) else {
            return nil
        }
        guard visited else {
            return false
        }
        if verified.count > 1000 {
            verified.removeAll()
        }
        verified[url] = now
        return true
    }
}
