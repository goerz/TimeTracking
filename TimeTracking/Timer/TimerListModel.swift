// TimerListModel: the list of recent entries by day (spec_timer_window.md §3).

import Foundation
import Observation
import TimeTrackingCore

/// The days shown, the filter, and the selection.
@Observable
final class TimerListModel {
    /// Days loaded at first and per "Load Earlier Entries".
    static let pageSize = 14

    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Called after a delete or restore.
    @ObservationIgnored var onChange: (() async -> Void)?
    @ObservationIgnored private(set) var pendingUndo: Task<Void, Never>?

    private(set) var days: [TimerListDay] = []
    private(set) var dayLimit = TimerListModel.pageSize
    /// Whether more days with entries exist than are loaded.
    private(set) var canLoadMore = false
    var filter = ""
    var isFilterVisible = false
    var selection: EntryID?
    /// Bumped by ⌘↑ (Scroll to Today).
    private(set) var scrollToTopRequest = 0

    init(store: TimeStore, clock: any Clock) {
        self.store = store
        self.clock = clock
    }

    /// The rows in display order.
    var rows: [EntryListing] {
        days.flatMap(\.rows)
    }

    func reload() async {
        do {
            days = try await store.timerList(dayLimit: dayLimit, filter: isFilterVisible ? filter : "")
            canLoadMore = try await store.entryDays(limit: dayLimit + 1).count > dayLimit
            if let selection, !rows.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        } catch {
            days = []
        }
    }

    /// "Load Earlier Entries", or scrolling to the end.
    func loadMore() async {
        guard canLoadMore else {
            return
        }
        dayLimit += Self.pageSize
        await reload()
    }

    /// The header title: "Today", "Yesterday", "Tue, Oct 27", with the year
    /// for other years.
    func title(for day: TrackingDay) -> String {
        let calendar = TrackingCalendar(timeZone: .current)
        let today = calendar.day(containing: clock.now)
        if day == today {
            return "Today"
        }
        if day == today.adding(days: -1) {
            return "Yesterday"
        }
        let date = calendar.startOfDay(day)
        let format = day.year == today.year ? "EEE, MMM d" : "EEE, MMM d, yyyy"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    // MARK: Selection and keys

    /// ↑ and ↓.
    func moveSelection(by offset: Int) {
        let ids = rows.map(\.id)
        guard !ids.isEmpty else {
            return
        }
        guard let selection, let index = ids.firstIndex(of: selection) else {
            selection = offset > 0 ? ids.first : ids.last
            return
        }
        self.selection = ids[min(max(index + offset, 0), ids.count - 1)]
    }

    /// Escape.
    func clearSelection() {
        selection = nil
    }

    /// ⌘↑.
    func scrollToTop() {
        scrollToTopRequest += 1
    }

    // MARK: Filter

    /// ⌘F shows the filter field.
    func showFilter() {
        isFilterVisible = true
    }

    /// Escape in the filter field clears and hides it.
    func hideFilter() async {
        filter = ""
        isFilterVisible = false
        await reload()
    }

    // MARK: Delete

    /// The delete alert's text: "0:25:00, Household".
    func deleteSummary(for listing: EntryListing) -> String {
        let duration = DurationText.clock(listing.entry.seconds(at: clock.now))
        return "\(duration), \(listing.project?.name ?? "No project")"
    }

    /// ⌘⌫ or Delete…: the alert for the selected row.
    func deleteAlert(for id: EntryID? = nil) -> TimerAlert? {
        guard let id = id ?? selection, let listing = rows.first(where: { $0.id == id }) else {
            return nil
        }
        return .deleteEntry(id, summary: deleteSummary(for: listing))
    }

    /// Deletes an entry; undoable with ⌘Z.
    func delete(_ id: EntryID) async {
        do {
            try await store.delete([id])
            if let undoManager {
                undoManager.registerUndo(withTarget: self) { model in
                    model.pendingUndo = Task { @MainActor in
                        try? await model.store.restore([id])
                        await model.reload()
                        await model.onChange?()
                    }
                }
                undoManager.setActionName("Delete Entry")
            }
            if selection == id {
                selection = nil
            }
            await reload()
            await onChange?()
        } catch {
            await reload()
        }
    }
}
