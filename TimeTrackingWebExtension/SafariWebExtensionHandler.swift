// SafariWebExtensionHandler: the Safari web extension's native handler
// (spec_ios.md §9.5).

import Foundation

final nonisolated class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: [], completionHandler: nil)
    }
}
