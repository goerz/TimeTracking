// OverlapNotice+Text: the inline overlap notice's text, shared by the
// edit popover and the iPhone's edit sheet (spec_timer.md §4.3;
// spec_ios.md §2.7).

import TimeTrackingCore

extension OverlapNotice {
    /// "Overlaps “Morning Review” (9:00 to 9:25)": the other entry's task,
    /// else its project's name, else "No task"; "now" for a running entry.
    static func text(for other: TimeEntry, in store: TimeStore) async -> String {
        var name = other.task
        if name.isEmpty, let listing = try? await store.listings(for: [other]).first {
            name = listing.project?.name ?? "No task"
        }
        let end = other.end.map(LocalDateText.time) ?? "now"
        return "Overlaps “\(name)” (\(LocalDateText.time(other.start)) to \(end))"
    }
}
