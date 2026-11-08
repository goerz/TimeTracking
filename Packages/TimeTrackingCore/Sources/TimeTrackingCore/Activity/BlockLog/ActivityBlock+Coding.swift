// ActivityBlock+Coding: one block as a line of a date file or the open
// block of current.json (activity_tracking.md §4.2, §4.4).

import Foundation

extension ActivityBlock {
    /// The block's JSON line, keys in the order of §4.2, empty values
    /// omitted, so equal blocks give equal text.
    public var jsonText: String {
        var writer = JSONObjectWriter()
        writer.add("s", ActivityTimestamp.textWithOffset(start, utcOffset: utcOffset))
        writer.add("e", ActivityTimestamp.textWithOffset(end, utcOffset: endUTCOffset))
        if let endReason {
            writer.add("r", endReason.rawValue)
        }
        if reconstructedSeconds != 0 {
            writer.add("rc", reconstructedSeconds)
        }
        if !foreground.isEmpty {
            writer.addRaw("f", "[\(foreground.map(\.jsonText).joined(separator: ","))]")
        }
        if !background.isEmpty {
            writer.addRaw("b", "[\(background.map(\.jsonText).joined(separator: ","))]")
        }
        return writer.text
    }

    /// The block of a decoded JSON object, or `nil` when `s` or `e` is
    /// missing or unreadable or `e` lies before `s`. Unknown keys are skipped.
    init?(json object: [String: Any], isOpen: Bool = false) {
        guard let start = (object["s"] as? String).flatMap(ActivityTimestamp.parseWithOffset),
              let end = (object["e"] as? String).flatMap(ActivityTimestamp.parseWithOffset),
              end.date >= start.date
        else {
            return nil
        }
        self.init(
            start: start.date,
            end: end.date,
            utcOffset: start.utcOffset,
            endUTCOffset: end.utcOffset,
            endReason: (object["r"] as? String).flatMap(ActivityEndReason.init(rawValue:)),
            reconstructedSeconds: object.int("rc"),
            foreground: Self.items(object["f"]),
            background: Self.items(object["b"]),
            isOpen: isOpen
        )
    }

    /// The block of one JSON line, `nil` for a malformed or non-block line.
    public init?(jsonLine: some StringProtocol) {
        guard let object = Self.jsonObject(jsonLine) else {
            return nil
        }
        self.init(json: object)
    }

    /// The JSON object of `text`, or `nil` for text that is no JSON object
    /// (a malformed line, which an empty object cannot express).
    static func jsonObject(_ text: some StringProtocol) -> [String: Any]? { // swiftlint:disable:this discouraged_optional_collection
        guard let data = String(text).data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func items(_ value: Any?) -> [ActivityBlockItem] {
        (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map(ActivityBlockItem.init(json:))
    }
}
