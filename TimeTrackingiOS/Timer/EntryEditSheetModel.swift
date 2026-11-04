// EntryEditSheetModel: the iPhone's edit sheet (spec_ios.md §2.7): a draft
// of task, project, start, and end that Done saves under the Mac Timer's
// future, overlap, and midnight rules (spec_timer.md §4.2, §4.3).

import Foundation
import Observation
import os
import TimeTrackingCore

/// The draft and its checks; nothing is written before Done.
@Observable
final class EntryEditSheetModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    /// After a save or delete.
    @ObservationIgnored var onChange: (() async -> Void)?

    private(set) var entry: TimeEntry?
    var task = ""
    private(set) var projectID: ProjectID?
    private(set) var label: ProjectLabel = .noProject
    var start = Date()
    var end = Date()
    /// "Created on MacBook".
    private(set) var createdOn: String?
    /// The adjustment explanation, if this entry was adjusted after syncing.
    var explanation: String?
    private(set) var message: String?
    /// "Overlaps “Morning Review” (9:00 to 9:25)", waiting for Keep or Revert.
    private(set) var overlap: String?

    static let futureMessage = EntryEditorModel.futureMessage
    static let orderMessage = "The end must be after the start"
    static let midnightNotice = "Will be saved as 2 entries, split at midnight"

    init(store: TimeStore, clock: any Clock) {
        self.store = store
        self.clock = clock
    }

    var isRunning: Bool {
        entry?.isRunning ?? false
    }

    func load(_ id: EntryID) async {
        guard let found = try? await store.entry(id) else {
            return
        }
        entry = found
        task = found.task
        start = found.start
        end = found.end ?? clock.now
        await setProject(found.projectID)
        let devices = await (try? store.devices()) ?? []
        createdOn = devices.first { $0.id == found.deviceID }.map { "Created on \($0.name)" }
    }

    func setProject(_ id: ProjectID?) async {
        projectID = id
        label = await ProjectLabel.loadLive(id, from: store)
    }

    /// The duration line: the draft's, or the live time of a running entry.
    func durationText(at now: Date) -> String {
        let seconds = isRunning ? now.timeIntervalSince(start) : end.timeIntervalSince(start)
        return DurationText.clock(max(0, Int(seconds)))
    }

    /// Shown under the duration before saving an interval across midnight.
    var midnightNoticeText: String? {
        guard let entry, !isRunning, EntryEditRules.crossesMidnight(start: start, end: end, in: entry.zone) else {
            return nil
        }
        return Self.midnightNotice
    }

    /// Done: checks the rules and saves; `true` when the sheet may close.
    func save() async -> Bool {
        guard let entry else {
            return true
        }
        message = nil
        if case let .failure(error) = EntryEditRules.check(start: start, end: isRunning ? nil : end, now: clock.now) {
            message = error == .inFuture ? Self.futureMessage : Self.orderMessage
            return false
        }
        let draft = EntryDraft(projectID: projectID, task: task, start: start, end: isRunning ? nil : end)
        if overlap == nil, let other = await (try? store.overlaps(for: draft, outsideChainOf: entry.id))?.first {
            overlap = await OverlapNotice.text(for: other, in: store)
            return false
        }
        return await write()
    }

    /// "Keep" on the overlap notice.
    func keepOverlap() async -> Bool {
        overlap = nil
        return await write()
    }

    /// "Revert" on the overlap notice: back to the stored times.
    func revertOverlap() {
        overlap = nil
        if let entry {
            start = entry.start
            end = entry.end ?? clock.now
        }
    }

    func delete() async {
        guard let entry else {
            return
        }
        try? await store.delete([entry.id])
        await onChange?()
    }

    private func write() async -> Bool {
        guard let entry else {
            return true
        }
        do {
            // Only what the sheet changed: a task stored meanwhile (the
            // card's field) stays when only the project or times change.
            let newTask = task.trimmed != entry.task ? task : nil
            let newProject = projectID != entry.projectID ? Optional(projectID) : nil
            if newTask != nil || newProject != nil {
                _ = try await store.updateChain(of: entry.id, task: newTask, projectID: newProject)
            }
            // Only the times the sheet changed: an end stored meanwhile on
            // another device stays when only the start changes.
            if let change = EntryEditResult(start: start, end: isRunning ? nil : end).changeIfAny(from: entry) {
                _ = try await store.update(entry.id, change)
            }
            await onChange?()
            return true
        } catch {
            Logging.logger(category: "Timer").error("Saving the entry failed: \(error.localizedDescription, privacy: .public)")
            message = UserMessage.text(for: error)
            return false
        }
    }
}
