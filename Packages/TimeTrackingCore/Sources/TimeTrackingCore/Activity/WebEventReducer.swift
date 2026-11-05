// WebEventReducer: what the Safari web extension keeps of a URL
// (ios.md §9.5, activity_tracking.md §7.2).

public import Foundation

/// Reduces a tab's URL to the label of a `webext` line, the exclusions
/// applied: a domain in `exclude_domains` is dropped, one in
/// `private_domains` becomes the bare domain, any other URL keeps domain
/// plus path (which carries the code host's owner and repository for the
/// Mac's group-key rule). Query strings, fragments, and titles are never kept.
public enum WebEventReducer {
    /// The label for `urlText`, or `nil` when it is dropped or not an
    /// http(s) URL with a host.
    public static func label(for urlText: String, exclusions: ExclusionRules) -> String? {
        guard let components = URLComponents(string: urlText),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else {
            return nil
        }
        if exclusions.excludesDomain(host) {
            return nil
        }
        let domain = BrowserItemRules.bareDomain(host) + (components.port.map { ":\($0)" } ?? "")
        if exclusions.isPrivateDomain(host) {
            return domain
        }
        let path = components.path.split(separator: "/").joined(separator: "/")
        return path.isEmpty ? domain : "\(domain)/\(path)"
    }

    /// The URL and time (milliseconds since 1970) of a message from the
    /// background script, `{"url": …, "time": …}`; a missing time is `nil`.
    public static func message(_ object: [String: Any]) -> (url: String, time: Date?)? {
        guard let url = object["url"] as? String else {
            return nil
        }
        let time = (object["time"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return (url, time)
    }
}
