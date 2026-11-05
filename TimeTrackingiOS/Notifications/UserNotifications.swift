// UserNotifications: the iOS app's notifications through
// UNUserNotificationCenter (ios.md §8). Actions run in the background.

import Foundation
import UserNotifications

/// Schedules the categories of `NotificationCategory` and forwards responses.
final class UserNotifications: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    /// The one instance, the notification center's delegate from launch on
    /// (`PhoneAppDelegate`), so a response that launches the app in the
    /// background is not lost while the store opens.
    static let shared = UserNotifications()

    private let center = UNUserNotificationCenter.current()
    /// An action button, or `nil` for a tap on the notification; the
    /// notification's entry id, if any. Awaited before the system is told;
    /// it waits for the model.
    var onResponse: (NotificationCategory?, NotificationAction?, String?) async -> Void = { category, action, entryID in
        let model = await PhoneIntentBridge.shared.awaitModel()
        await model.handleNotification(category, action, entryID: entryID)
    }

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories(Set(NotificationCategory.allCases.map(Self.category)))
    }

    static func category(_ category: NotificationCategory) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: category.rawValue,
            actions: category.actions.map { action in
                UNNotificationAction(identifier: action.rawValue, title: action.title, options: [])
            },
            intentIdentifiers: []
        )
    }

    func requestAuthorization() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    func schedule(_ notification: ScheduledNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.categoryIdentifier = notification.category.rawValue
        content.sound = notification.category.notificationSound(notification.sound)
        content.interruptionLevel = switch notification.category.level {
        case .passive: .passive
        case .active: .active
        case .timeSensitive: .timeSensitive
        }
        if let entryID = notification.entryID {
            content.userInfo = ["entryID": entryID]
        }
        let trigger = notification.date.map { date in
            UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        }
        let request = UNNotificationRequest(identifier: notification.category.rawValue, content: content, trigger: trigger)
        Task { try? await center.add(request) }
    }

    func remove(_ categories: [NotificationCategory]) {
        let ids = categories.map(\.rawValue)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let category = NotificationCategory(rawValue: content.categoryIdentifier)
        let action = NotificationAction(rawValue: response.actionIdentifier)
        let entryID = content.userInfo["entryID"] as? String
        await respond(category, action, entryID)
    }

    private func respond(_ category: NotificationCategory?, _ action: NotificationAction?, _ entryID: String?) async {
        await onResponse(category, action, entryID)
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
