// PhoneModel+Notifications: the Device record, the widget push token, the
// long-running reminder, and notification actions (spec_ios.md §4 item 1, §8).

import Foundation
import TimeTrackingCore

extension PhoneModel {
    // MARK: Device record and push token

    /// The name on this device's `Device` record: the one set in Settings,
    /// else the system's.
    var deviceDisplayName: String {
        settings.deviceName.isEmpty ? DeviceInfo.systemName : settings.deviceName
    }

    func registerDevice() async {
        _ = try? await store.registerDevice(name: deviceDisplayName, platform: settings.isPad ? .ipad : .iphone)
    }

    /// Records the stored widget push token on this device's `Device` record
    /// (spec_ios.md §4 item 1); repeated, so a lost write repairs itself.
    func uploadPushToken() async {
        guard let token = shared.pushToken else {
            return
        }
        do {
            try await store.setWidgetPushToken(token)
        } catch StoreError.unknownID {
            await registerDevice()
            try? await store.setWidgetPushToken(token)
        } catch {
            return
        }
    }

    // MARK: Long-running reminder

    /// Schedules `longRunning` at the running entry's start plus N hours,
    /// whichever device started it; removes it when nothing runs.
    func rescheduleLongRunning() {
        guard settings.longRunningEnabled, let running = timer.running else {
            if lastLongRunningKey != nil || timer.running == nil {
                notifications.remove([.longRunning])
            }
            lastLongRunningKey = nil
            return
        }
        let key = "\(running.id)-\(settings.longRunningHours)-\(running.task)"
        guard key != lastLongRunningKey else {
            return
        }
        lastLongRunningKey = key
        scheduleLongRunning(at: running.start + TimeInterval(settings.longRunningHours * 3600), elapsedHours: settings.longRunningHours)
    }

    func scheduleLongRunning(at date: Date, elapsedHours: Int) {
        let task = timer.running?.task ?? ""
        let subject = task.isEmpty ? (timer.runningLabel.isNone ? "this entry" : timer.runningLabel.name) : task
        notifications.schedule(ScheduledNotification(
            category: .longRunning,
            title: "Still tracking \(subject)?",
            body: "Running for \(elapsedHours) hour\(elapsedHours == 1 ? "" : "s").",
            date: max(date, clock.now + 1),
            // Its Stop acts on this entry only (IOS-45).
            entryID: timer.running?.id.rawValue
        ))
    }

    /// A notification action or a tap (spec_ios.md §8).
    func handleNotification(_ category: NotificationCategory?, _ action: NotificationAction?, entryID: String?) async {
        await timer.refresh()
        pomodoro.replay(isRunning: timer.isRunning)
        switch action {
        case .startBreak: pomodoro.perform(.startBreak, isRunning: timer.isRunning)
        case .skipBreak: pomodoro.perform(.skipBreak, isRunning: timer.isRunning)
        case .startFocus: pomodoro.perform(.startFocus, isRunning: timer.isRunning)
        case .endPomodoro: pomodoro.perform(.cancel, isRunning: timer.isRunning)
        case .keep:
            let hours = timer.running.map { Int(clock.now.timeIntervalSince($0.start) / 3600) } ?? settings.longRunningHours
            scheduleLongRunning(
                at: clock.now + TimeInterval(settings.longRunningHours * 3600),
                elapsedHours: hours + settings.longRunningHours
            )
        case .stop:
            if let id = entryID.flatMap({ EntryID($0) }) {
                await timer.stop(entry: id)
            } else {
                await timer.stop()
            }
        case nil:
            if category == .syncAdjusted, let id = entryID.flatMap({ EntryID($0) }) {
                openEditor(id)
            }
        }
    }
}
