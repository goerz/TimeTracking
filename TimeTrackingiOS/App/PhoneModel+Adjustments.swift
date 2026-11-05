// PhoneModel+Adjustments: the adjustment banner and badges, and the picker
// sheet with its project dialog (ios.md §2.4, §7 item 3).

import Foundation
import TimeTrackingCore

extension PhoneModel {
    // MARK: Adjustments

    func showAdjustments(_ adjustments: [EntryAdjustment]) async {
        guard let adjustment = adjustments.last else {
            return
        }
        let devices = await (try? store.devices()) ?? []
        for item in adjustments {
            let device = devices.first { $0.id == item.causingDeviceID }?.name
            explanations[item.entryID] = Self.explanation(item, deviceName: device)
            badged.insert(item.entryID)
        }
        settings.device[.badgedEntries] = badged.map(\.rawValue)
        let explanation = explanations[adjustment.entryID] ?? ""
        banner = AdjustmentBanner(entryID: adjustment.entryID, explanation: explanation)
        if !isActive {
            notifications.schedule(ScheduledNotification(
                category: .syncAdjusted,
                title: "An entry was changed",
                body: explanation,
                date: nil,
                entryID: adjustment.entryID.rawValue
            ))
        }
    }

    /// "Stopped at 10:14 because an entry started on MacBook".
    static func explanation(_ adjustment: EntryAdjustment, deviceName: String?) -> String {
        let device = deviceName.map { " on \($0)" } ?? " on another device"
        switch adjustment.reason {
        case .stoppedByLaterStart:
            let end = adjustment.after?.end.map(LocalDateText.time) ?? ""
            return "Stopped at \(end) because an entry started\(device)"
        case .removedByLaterStart:
            return "Removed because an entry started\(device)"
        case .replacedByRemoteEdit:
            return "Replaced by an edit\(device)"
        case .deletedRemotely:
            return "Deleted\(device)"
        case .restoredRemotely:
            return "Restored\(device)"
        }
    }

    /// "Show" in the banner, or a row tap.
    func openEditor(_ id: EntryID) {
        banner = nil
        if badged.remove(id) != nil {
            settings.device[.badgedEntries] = badged.map(\.rawValue)
        }
        sheet = .editor(id)
    }

    // MARK: Picker and project dialog

    /// The chip, or `@` in the task field (with the search after it).
    func openPicker(search: String = "") {
        let picker = ProjectPickerModel(store: store, currentProject: timer.chipProjectID, taskMatching: true)
        picker.search = search
        dialogModel = nil
        sheet = .picker(picker)
    }

    /// A choice in the picker sheet.
    func choose(_ choice: ProjectPickerChoice) async {
        switch choice {
        case let .project(id):
            sheet = nil
            await timer.assignPicked(id)
        case let .create(name):
            dialogModel = ProjectDialogModel(store: store, mode: .create, name: name)
        }
    }

    /// The dialog inside the picker sheet finished; Create assigns and closes.
    func dialogFinished(_ project: Project?) async {
        dialogModel = nil
        guard let project else {
            return
        }
        sheet = nil
        await timer.assignPicked(project.id)
    }
}
