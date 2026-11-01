// The id in a Calendar drag payload such as "block:<id>"
// (spec_calendar.md §3.3, §4.4).

extension String {
    /// The rest after `prefix`, or `nil`.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
