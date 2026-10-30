// ResolveContext: settings, exclusions, and path rules shared by the
// resolvers (spec_activity_tracking.md §2.2 rule 3, §7.2).

import Foundation
import TimeTrackingCore

/// What every resolver needs: the settings, the exclusions, `~`, and the
/// work-folder rule for group keys.
struct ResolveContext {
    var settings: TrackerSettings
    var exclusions: ExclusionRules
    var homeDirectory: String
    var files: any FileProbe
    private var workFolders: [String: String] = [:]

    init(settings: TrackerSettings, homeDirectory: String, files: any FileProbe) {
        self.settings = settings
        self.exclusions = settings.exclusions(homeDirectory: homeDirectory)
        self.homeDirectory = homeDirectory
        self.files = files
    }

    /// `path` with the home folder written `~`; `file://` URLs become paths.
    func tilde(_ path: String) -> String {
        let plain = Self.plainPath(path)
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        guard !home.isEmpty, home != "/" else {
            return plain
        }
        if plain == home {
            return "~"
        }
        if plain.lowercased().hasPrefix(home.lowercased() + "/") {
            return "~" + plain.dropFirst(home.count)
        }
        return plain
    }

    /// `path` with `~` expanded.
    func expand(_ path: String) -> String {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return (homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory) + path.dropFirst()
        }
        return Self.plainPath(path)
    }

    /// A path from a `file://` URL or a plain path, without a trailing slash.
    static func plainPath(_ text: String) -> String {
        var path = text
        if text.lowercased().hasPrefix("file://"), let url = URL(string: text) {
            path = url.path(percentEncoded: false)
        }
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// The work folder of a folder (§2.2 rule 3), written with `~`: the
    /// nearest ancestor containing a `root_markers` entry, else the folder
    /// `group_depth` levels below its watched root, one level deeper below
    /// a `deep_folders` entry; outside the roots, the folder itself.
    mutating func workFolder(ofFolder folder: String) -> String {
        let absolute = expand(folder)
        if let cached = workFolders[absolute] {
            return cached
        }
        let result = tilde(computeWorkFolder(absolute))
        if workFolders.count > 512 {
            workFolders.removeAll()
        }
        workFolders[absolute] = result
        return result
    }

    /// The work folder of a file's folder.
    mutating func workFolder(ofFile file: String) -> String {
        let absolute = expand(file)
        let folder = (absolute as NSString).deletingLastPathComponent
        return workFolder(ofFolder: folder.isEmpty ? "/" : folder)
    }

    private func computeWorkFolder(_ folder: String) -> String {
        let home = expand("~")
        var current = folder
        while current.count > 1 {
            if settings.files.rootMarkers.contains(where: { files.exists(current + "/" + $0) }) {
                return current
            }
            if current == home {
                break
            }
            current = (current as NSString).deletingLastPathComponent
        }
        for deep in settings.files.deepFolders.map(expand) {
            if let rest = Self.relative(folder, to: deep), let first = rest.first {
                return deep + "/" + first
            }
        }
        for root in settings.files.roots.map(expand) {
            if let rest = Self.relative(folder, to: root) {
                let depth = max(0, settings.files.groupDepth)
                return rest.count <= depth ? folder : ([root] + rest.prefix(depth)).joined(separator: "/")
            }
        }
        return folder
    }

    /// The components of `path` below `base`, or `nil` if it is not at or below it.
    private static func relative(_ path: String, to base: String) -> [String]? {
        let lowerPath = path.lowercased()
        let lowerBase = base.lowercased()
        if lowerPath == lowerBase {
            return []
        }
        guard lowerPath.hasPrefix(lowerBase + "/") else {
            return nil
        }
        return path.dropFirst(base.count + 1).split(separator: "/").map(String.init)
    }

    // MARK: Exclusions

    /// The item for an app in `name_only_apps`: its name only.
    static func nameOnly(_ item: SampleItem) -> SampleItem {
        SampleItem(context: item.context, subject: "", detail: "", groupKey: item.context, app: item.app)
    }

    /// Applies `exclude_title_keywords` to a window title.
    func filteredTitle(_ title: String) -> String {
        exclusions.excludesTitle(title) ? "" : title
    }

    /// Hides an item whose path is excluded: subject and detail
    /// `(private)`, group key `private` unless `keepGroup`.
    static func privatePath(_ item: SampleItem, keepGroup: Bool = false) -> SampleItem {
        SampleItem(
            context: item.context,
            subject: ExclusionRules.privateMarker,
            detail: ExclusionRules.privateMarker,
            groupKey: keepGroup ? item.groupKey : ExclusionRules.privateGroupKey,
            app: item.app
        )
    }
}
