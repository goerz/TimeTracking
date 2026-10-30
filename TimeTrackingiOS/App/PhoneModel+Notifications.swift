// PhoneModel+Notifications: the Device record, the widget push token, the
// long-running reminder, and notification actions (spec_ios.md §4 item 1, §8).

import Foundation
import TimeTrackingCore

extension PhoneModel {
    // MARK: Device record and push token

    func registerDevice() async {
        let name = settings.deviceName.isEmpty ? DeviceInfo.systemName : settings.deviceName
        _ = try? await store.registerDevice(name: name, platform: settings.isPad ? .ipad : .iphone)
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

    /// Schedules `longRunning` at the running chain's start plus N hours,
    /// whichever device started it; removes it when nothing runs.
    func rescheduleLongRunning() {
        guard settings.longRunningEnabled, let running = timer.running, let chainStart = timer.chainStart else {
            if lastLongRunningKey != nil || timer.running == nil {
                notifications.remove([.longRunning])
            }
            lastLongRunningKey = nil
            return
        }
        let key = "\(running.rootID)-\(settings.longRunningHours)-\(running.task)"
        guard key != lastLongRunningKey else {
            return
        }
        lastLongRunningKey = key
        scheduleLongRunning(at: chainStart + TimeInterval(settings.longRunningHours * 3600), elapsedHours: settings.longRunningHours)
    }

    func scheduleLongRunning(at date: Date, elapsedHours: Int) {
        let task = timer.running?.task ?? ""
        let subject = task.isEmpty ? (timer.runningLabel.isNone ? "this entry" : timer.runningLabel.name) : task
        notifications.schedule(ScheduledNotification(
            category: .longRunning,
            title: "Still tracking \(subject)?",
            body: "Running for \(elapsedHours) hour\(elapsedHours == 1 ? "" : "s").",
            date: max(date, clock.now + 1)
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
            let hours = timer.chainStart.map { Int(clock.now.timeIntervalSince($0) / 3600) } ?? settings.longRunningHours
            scheduleLongRunning(
                at: clock.now + TimeInterval(settings.longRunningHours * 3600),
                elapsedHours: hours + settings.longRunningHours
            )
        case .stop:
            await timer.stop()
        case nil:
            if category == .syncAdjusted, let id = entryID.flatMap({ EntryID($0) }) {
                openEditor(id)
            }
        }
    }
}
