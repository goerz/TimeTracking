// Sample+Coding: a Sample's Items as stored in samples.sqlite, with the
// short keys of the block log (activity_tracking.md §4.1, §4.2).

import Foundation

extension Sample {
    /// `{"f":{…},"b":[…]}`, the Items with the keys of §4.2; `f` is
    /// omitted without a foreground Item, `b` without background Items.
    var itemsJSON: String {
        var writer = JSONObjectWriter()
        if let foreground {
            writer.addRaw("f", foreground.jsonText)
        }
        if !background.isEmpty {
            writer.addRaw("b", "[\(background.map(\.jsonText).joined(separator: ","))]")
        }
        return writer.text
    }

    /// The Items of a stored `items` text; unreadable text gives none.
    static func items(fromJSON text: String) -> (foreground: ActivityItem?, background: [ActivityItem]) {
        guard let object = ActivityBlock.jsonObject(text) else {
            return (nil, [])
        }
        let foreground = (object["f"] as? [String: Any]).map(ActivityItem.init(json:))
        let background = (object["b"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map(ActivityItem.init(json:))
        return (foreground, background)
    }
}
