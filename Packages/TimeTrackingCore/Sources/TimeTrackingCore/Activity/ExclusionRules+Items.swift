// ExclusionRules+Items: applying the exclusions to items, blocks, and detail
// lines already recorded (spec_activity_tracking.md §7.2, §7.3).

import Foundation

extension ExclusionRules {
    /// The marker of hidden subjects, details, and sessions.
    public static let privateMarker = "(private)"
    /// The group key of items under an excluded path.
    public static let privateGroupKey = "private"

    /// `item` under the current exclusions, judged from its recorded text;
    /// `nil` when nothing of it may be recorded (`exclude_apps`).
    ///
    /// Recorded details hold file names, not paths, so a file is caught by
    /// its subject's folder or a keyword, not by `exclude_paths` alone.
    public func reapplied(to item: ActivityItem, bundleIdentifier: String?) -> ActivityItem? {
        var result = item
        if let bundleIdentifier, !bundleIdentifier.isEmpty, excludesApp(bundleIdentifier) {
            return nil
        }
        if excludesApp(item.context) {
            return nil
        }
        if item.context.lowercased().hasPrefix("tmux:"), excludesTmuxSession(String(item.context.dropFirst(5))) {
            return ActivityItem(context: "tmux:\(Self.privateMarker)", subject: "", detail: "", seconds: item.seconds)
        }
        if let bundleIdentifier, isNameOnlyApp(bundleIdentifier) {
            result.subject = ""
            result.detail = ""
            return result
        }
        let host = Self.leadingHost(item.subject)
        if let host, excludesDomain(host) {
            return ActivityItem(context: item.context, subject: Self.privateMarker, detail: "", seconds: item.seconds)
        }
        if let host, isPrivateDomain(host) {
            result.subject = host
            result.detail = ""
        }
        if excludesRecordedText(item.subject) || excludesRecordedText(item.detail) {
            result.subject = Self.privateMarker
            result.detail = Self.privateMarker
            return result
        }
        if excludesTitle(result.subject) {
            result.subject = ""
        }
        if excludesTitle(result.detail) {
            result.detail = ""
        }
        return result
    }

    /// `block` under the current exclusions, `nil` when every item is
    /// excluded. Removed items' seconds leave `a`; equal items merge; an
    /// excluded group key becomes the largest remaining item's.
    public func reapplied(to block: ActivityBlock, contexts: [String: String]) -> ActivityBlock? {
        let items = reapplied(block.items, contexts: contexts)
        let background = reapplied(block.background, contexts: contexts)
        guard !items.isEmpty || block.items.isEmpty else {
            return nil
        }
        var result = block
        let removed = block.items.reduce(0) { $0 + $1.seconds } - items.reduce(0) { $0 + $1.seconds }
        result.items = items
        result.background = background
        result.activeSeconds = max(0, block.activeSeconds - max(0, removed))
        if let key = reappliedGroupKey(block.groupKey, items: items, contexts: contexts), key != block.groupKey {
            result.groupKey = key
            let seconds = items.filter { $0.context == key }.reduce(0) { $0 + $1.seconds }
            result.groupShare = result.activeSeconds > 0 ? min(1, (Double(seconds) / Double(result.activeSeconds) * 100).rounded() / 100) : 0
        }
        return result
    }

    /// `detail` under the current exclusions: items as for blocks, visits to
    /// `exclude_domains` and files under excluded paths dropped,
    /// `private_domains` visits reduced to the domain, excluded titles dropped.
    public func reapplied(to detail: ActivityBlockDetail, contexts: [String: String]) -> ActivityBlockDetail {
        var result = detail
        result.items = reapplied(detail.items, contexts: contexts)
        result.urls = detail.urls.compactMap { visit in
            guard !excludesDomain(visit.url) else {
                return nil
            }
            var kept = visit
            if isPrivateDomain(visit.url), let components = URLComponents(string: visit.url), let host = components.host {
                kept.url = "\(components.scheme ?? "https")://\(host)"
                kept.title = ""
            }
            if excludesTitle(kept.title) {
                kept.title = ""
            }
            return kept
        }
        result.files = detail.files.filter { !excludesPath($0.path) }
        result.dwell = detail.dwell.filter { !excludesDomain($0.url) }
        return result
    }

    // MARK: Helpers

    private func reapplied(_ items: [ActivityItem], contexts: [String: String]) -> [ActivityItem] {
        var merged: [ActivityItem] = []
        for item in items {
            guard let kept = reapplied(to: item, bundleIdentifier: contexts[item.context]) else {
                continue
            }
            if let index = merged.firstIndex(where: { $0.context == kept.context && $0.subject == kept.subject && $0.detail == kept.detail }) {
                merged[index].seconds += kept.seconds
            } else {
                merged.append(kept)
            }
        }
        return merged
    }

    private func reappliedGroupKey(_ key: String, items: [ActivityItem], contexts: [String: String]) -> String? {
        if key.lowercased().hasPrefix("tmux:"), excludesTmuxSession(String(key.dropFirst(5))) {
            return "tmux:\(Self.privateMarker)"
        }
        if excludesApp(key) || (contexts[key].map(excludesApp) ?? false) || excludesDomain(key) {
            return items.max { $0.seconds < $1.seconds }?.context
        }
        if key.hasPrefix("/") || key.hasPrefix("~"), excludesPath(key) {
            return Self.privateGroupKey
        }
        if let host = Self.leadingHost(key), isPrivateDomain(host) {
            return host
        }
        return nil
    }

    /// Whether a recorded subject or detail names an excluded path: the text
    /// is such a path, or a word or path component starts with a keyword.
    private func excludesRecordedText(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        for word in text.split(separator: " ") where word.hasPrefix("/") || word.hasPrefix("~") || word.hasPrefix("file://") {
            if excludesPath(String(word)) {
                return true
            }
        }
        if text.hasPrefix("/") || text.hasPrefix("~"), excludesPath(text) {
            return true
        }
        let words = text.lowercased().split { $0 == " " || $0 == "/" }
        return excludeKeywords.contains { keyword in
            let prefix = keyword.lowercased()
            return !prefix.isEmpty && words.contains { $0.hasPrefix(prefix) }
        }
    }

    /// The host at the start of a browser subject such as `github.com/owner`.
    private static func leadingHost(_ subject: String) -> String? {
        guard !subject.hasPrefix("/"), !subject.hasPrefix("~") else {
            return nil
        }
        let head = subject.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        let host = head.split(separator: ":").first.map(String.init) ?? ""
        guard host.contains("."), !host.contains(" ") else {
            return nil
        }
        return host
    }
}
