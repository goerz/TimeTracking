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
            application.registerForRemoteNotifications()
        }
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
                }
            )
            await handler.handle { inTime in
                completionHandler(inTime ? .newData : .failed)
            }
        }
    }
}
