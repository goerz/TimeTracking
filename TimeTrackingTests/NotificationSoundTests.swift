// The sound of a notification (timer.md §5.2, §10).

import Foundation
import Testing
import TimeTrackingCore
import UserNotifications
@testable import TimeTracking

@MainActor
struct NotificationSoundTests {
    @Test("TM-53 with Play a sound off a phase's notification is silent; on, it has its bundled sound; other categories use the default")
    func phaseSound() async throws {
        let test = try await TestApp()
        test.app.pomodoro.sleepUntil = { _ in try await Task.sleep(for: .seconds(3600)) }
        await test.app.timer.start()
        test.app.settings.pomodoroSounds = false
        test.app.perform(.start)
        test.clock.advance(by: 25 * 60)
        test.app.pomodoro.tick()
        let silent = try #require(test.notifier.posted.last)
        #expect(silent.category == .pomodoroFocusDone)
        #expect(silent.category.notificationSound(silent.sound) == nil)
        #expect(NotificationCategory.pomodoroBreakDone.notificationSound(nil) == nil)
        #expect(NotificationCategory.pomodoroFocusDone.notificationSound(.focusEnd) != nil)
        for category in [NotificationCategory.idle, .reminder, .tracking] {
            #expect(category.notificationSound(nil) == .default)
        }
    }
}
