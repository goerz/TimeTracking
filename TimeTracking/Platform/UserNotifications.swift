// UserNotifications: the Mac app's notifications through
// UNUserNotificationCenter (spec_timer_window.md §10).

import Foundation
import UserNotifications

/// Posts the categories of `NotificationCategory` and forwards responses.
final class UserNotifications: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// An action button, or `nil` for a click on the notification.
    var onResponse: (NotificationCategory?, NotificationAction?) -> Void = { _, _ in }

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories(Set(NotificationCategory.allCases.map(Self.category)))
    }

    static func category(_ category: NotificationCategory) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: category.rawValue,
            actions: category.actions.map { UNNotificationAction(identifier: $0.rawValue, title: $0.title) },
            intentIdentifiers: []
        )
    }

    static func isAuthorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    func requestAuthorization() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func post(_ request: NotificationRequest) {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.categoryIdentifier = request.category.rawValue
        content.sound = request.sound.map { UNNotificationSound(named: UNNotificationSoundName($0.rawValue)) } ?? .default
        let notification = UNNotificationRequest(identifier: request.category.rawValue, content: content, trigger: nil)
        Task { try? await center.add(notification) }
    }

    func remove(_ categories: [NotificationCategory]) {
        let ids = categories.map(\.rawValue)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: () -> Void
    ) {
        let category = NotificationCategory(rawValue: response.notification.request.content.categoryIdentifier)
        let action = NotificationAction(rawValue: response.actionIdentifier)
        Task { @MainActor in
            self.onResponse(category, action)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
