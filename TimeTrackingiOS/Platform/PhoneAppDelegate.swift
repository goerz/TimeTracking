// PhoneAppDelegate: the UIKit glue SwiftUI has no equivalent for: remote
// notification registration and the silent-push callback (spec_ios.md §7
// item 1), and the device's name and idiom (spec_ios.md §11, §10).

import TimeTrackingCore
import UIKit

/// Registers for remote notifications and hands silent pushes to the model.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        // swiftlint:disable:next discouraged_optional_collection
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if !LaunchArguments.current.uiTesting {
            // The delegate before anything awaits: a notification action
            // that launched the app is delivered to it.
            _ = UserNotifications.shared
            application.registerForRemoteNotifications()
        }
        // The store opens at launch, also without a window (a silent push,
        // a widget button, a notification action).
        Task { await PhoneHost.shared.load() }
        return true
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification _: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let model = await PhoneIntentBridge.shared.awaitModel()
            let handler = SilentPushHandler(
                fetch: { await model.sync?.fetchNow() },
                fanOut: {
                    await model.uploadPushToken()
                    await model.fanOut(structureChanged: true)
                    // Every CloudKit push flushes the collection (spec_ios.md §9.6).
                    await model.collection.flush()
                }
            )
            await handler.handle { inTime in
                completionHandler(inTime ? .newData : .failed)
            }
        }
    }
}
