// SafariWebExtensionHandler: the Safari web extension's native handler
// (ios.md §9.5). It forwards each `{url, time}` message to the
// library's CollectionLog with the exclusions of the App Group copy of
// settings.toml, and answers whether a line was written.

import Foundation
import os
import SafariServices
import TimeTrackingCore

final nonisolated class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let logger = Logging.logger(category: "WebExtension")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        var logged = false
        if let message, let parsed = WebEventReducer.message(message), let identity = AppIdentity.main,
           let log = CollectionLog.extensionLog(identity: identity), let folder = CollectionLog.folder(identity: identity)
        {
            do {
                logged = try log.logWeb(url: parsed.url, at: parsed.time, exclusions: CollectionLog.exclusions(folder: folder))
            } catch {
                Self.logger.error("Logging a tab failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["logged": logged]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
