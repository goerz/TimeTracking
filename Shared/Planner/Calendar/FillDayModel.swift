// FillDayModel: the Fill Day review sheet (spec_planner_calendar.md §3.5).

import Foundation
import Observation
import TimeTrackingCore

/// One row of the sheet as the user edits it.
struct FillDayRow: Identifiable, Equatable {
    var proposal: FillDayProposal
    var checked: Bool
    var projectID: ProjectID?
    var task: String

    var id: Date {
        proposal.id
    }
}

/// The review sheet: rows, checks, edits, Log, Cancel.
@Observable
final class FillDayModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored var onFinish: () async -> Void = {}
    let day: TrackingDay
    var rows: [FillDayRow]
    /// Rows removed with Skip (recorded as `skipped`).
    private(set) var removed: [FillDayProposal] = []
    @ObservationIgnored var pendingUndo: Task<Void, Never>?

    init(store: TimeStore, day: TrackingDay, proposals: [FillDayProposal]) {
        self.store = store
        self.day = day
        self.rows = proposals.map { proposal in
            let top = proposal.startsChecked ? proposal.top : nil
            return FillDayRow(proposal: proposal, checked: proposal.startsChecked, projectID: top?.projectID, task: top?.task ?? "")
        }
    }

    /// "Log 5 entries (3h 40m)".
    var logTitle: String {
        let checked = rows.filter(\.checked)
        let seconds = checked.reduce(0) { $0 + Int($1.proposal.interval.duration) }
        let noun = checked.count == 1 ? "entry" : "entries"
        return "Log \(checked.count) \(noun) (\(DurationText.hoursMinutes(seconds)))"
    }

    /// Editing a row checks it.
    func setProject(_ project: ProjectID?, row id: Date) {
        update(id) { row in
            row.projectID = project
            row.checked = true
        }
    }

    func setTask(_ task: String, row id: Date) {
        update(id) { row in
            row.task = task
            row.checked = true
        }
    }

    func toggle(_ id: Date) {
        update(id) { $0.checked.toggle() }
    }

    /// Skip removes the row.
    func skip(_ id: Date) {
        if let row = rows.first(where: { $0.id == id }) {
            removed.append(row.proposal)
        }
        rows.removeAll { $0.id == id }
    }

    private func update(_ id: Date, _ change: (inout FillDayRow) -> Void) {
        if let index = rows.firstIndex(where: { $0.id == id }) {
            change(&rows[index])
        }
    }

    /// Creates the checked rows in one transaction and one undo step; every
    /// unchecked or removed row records `skipped`.
    func log() async throws {
        let checked = rows.filter(\.checked).map { FillDayChoice(proposal: $0.proposal, projectID: $0.projectID, task: $0.task) }
        let skipped = rows.filter { !$0.checked }.map(\.proposal) + removed
        let created = try await store.logFillDay(checked: checked, skipped: skipped)
        let ids = created.map(\.id)
        if let undoManager, !ids.isEmpty {
            undoManager.registerUndo(withTarget: self) { model in
                model.pendingUndo = Task { @MainActor in
                    try? await model.store.delete(ids)
                    await model.onFinish()
                }
            }
            undoManager.setActionName("Fill Day")
        }
        await onFinish()
    }
}

extension CalendarModel {
    /// The day Fill Day works on from the toolbar: today when visible, else the first visible day.
    var fillDayTarget: TrackingDay {
        days.contains(today) ? today : firstDay
    }

    /// Whether a visible day has an untracked segment of at least `fillMinMinutes`.
    var canFillDay: Bool {
        let tracked = entries.map { $0.entry.interval(at: clock.now) }
        return blocks.contains { block in
            !block.isOpen && CalendarCoverage.uncovered(
                DateInterval(start: block.start, end: max(block.start, min(block.end, clock.now))),
                by: tracked
            )
            .contains { $0.duration >= Double(fillMinMinutes * 60) }
        }
    }

    /// ⇧⌘F or a header's sparkle: proposals for `day` in the review sheet.
    func openFillDay(_ day: TrackingDay? = nil) async {
        let day = day ?? fillDayTarget
        let interval = calendar.interval(of: day)
        do {
            let dayBlocks = try await activity.blocks(in: interval, devices: nil)
            let tracked = try await store.entries(in: interval, includeDeleted: false).map { $0.interval(at: clock.now) }
            let feedback = try await store.feedback(in: DateInterval(
                start: clock.now - Double(FillDay.skipMemoryDays) * 86_400,
                end: clock.now + 1
            ))
            let titles = (timeBlocks.map(\.event) + externalEvents).map { SuggestionCalendarTitle(title: $0.title, interval: $0.interval) }
            let context = await FillDay.Context(
                index: engine.index,
                rules: rules,
                titles: titles,
                feedback: feedback,
                fillMinMinutes: fillMinMinutes,
                now: clock.now,
                timeZone: calendar.timeZone
            )
            let model = FillDayModel(
                store: store,
                day: day,
                proposals: FillDay.proposals(day: interval, blocks: dayBlocks, entries: tracked, context: context)
            )
            model.undoManager = undoManager
            model.onFinish = { [weak self] in await self?.changed() }
            fillDay = model
        } catch {
            report(error)
        }
    }

    /// Log in the sheet.
    func logFillDay() async {
        guard let fillDay else {
            return
        }
        do {
            try await fillDay.log()
            self.fillDay = nil
        } catch {
            report(error)
        }
    }

    /// Cancel (Escape) writes nothing.
    func cancelFillDay() {
        fillDay = nil
    }
}
