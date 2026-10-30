// FileActivityStore+Exclusions: applying settings.toml's exclusions to blocks
// already in the logs (spec_activity_tracking.md §7.2, spec_data_and_sync.md §6).

import Foundation

extension FileActivityStore {
    /// `block` without the items whose context is excluded: an app in
    /// `exclude_apps` (through the header's context map) or a
    /// `tmux:<session>` in `exclude_tmux_sessions`. The removed items'
    /// seconds leave the active seconds; an excluded group key passes to the
    /// largest remaining item. A block whose items are all excluded is `nil`.
    static func applying(
        _ rules: ExclusionRules,
        to block: ActivityBlock,
        contexts: [String: String],
        fallback: [String: String]
    ) -> ActivityBlock? {
        func isExcluded(_ context: String) -> Bool {
            rules.excludesContext(context, bundleIdentifier: contexts[context] ?? fallback[context])
        }
        let items = block.items.filter { !isExcluded($0.context) }
        let background = block.background.filter { !isExcluded($0.context) }
        guard items.count != block.items.count || background.count != block.background.count else {
            return block
        }
        guard !items.isEmpty || block.items.isEmpty else {
            return nil
        }
        var result = block
        let removed = block.items.filter { isExcluded($0.context) }.reduce(0) { $0 + $1.seconds }
        result.items = items
        result.background = background
        result.activeSeconds = max(0, block.activeSeconds - removed)
        if isExcluded(block.groupKey), let top = items.max(by: { $0.seconds < $1.seconds }) {
            result.groupKey = top.context
            result.groupShare = result.activeSeconds > 0 ? min(1, Double(top.seconds) / Double(result.activeSeconds)) : 0
        }
        return result
    }

    /// `detail` without excluded items, visits to `exclude_domains`, and
    /// files under `exclude_paths` or `exclude_keywords`.
    static func applying(_ rules: ExclusionRules, to detail: ActivityBlockDetail, contexts: [String: String]) -> ActivityBlockDetail {
        var result = detail
        result.items = detail.items.filter { !rules.excludesContext($0.context, bundleIdentifier: contexts[$0.context]) }
        result.urls = detail.urls.filter { !rules.excludesDomain($0.url) }
        result.files = detail.files.filter { !rules.excludesPath($0.path) }
        return result
    }
}
