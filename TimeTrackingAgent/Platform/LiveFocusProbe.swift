// LiveFocusProbe: the frontmost app and its focused window through
// Accessibility (activity_tracking.md §2.4 step 2; no Screen Recording).

import AppKit
import ApplicationServices

/// `NSWorkspace` for the frontmost app; `AXTitle`, `AXDocument`, and, for
/// browsers, the web area's `AXURL`.
struct LiveFocusProbe: FocusProbe {
    /// The most elements searched for a browser's web area.
    static let searchLimit = 300

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func frontmostApp() -> FrontApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return FrontApp(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "", pid: app.processIdentifier)
    }

    func focusedWindow(of app: FrontApp) -> WindowInfo? {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let window = Self.element(application, kAXFocusedWindowAttribute) else {
            return nil
        }
        let title = Self.string(window, kAXTitleAttribute) ?? ""
        let document = Self.string(window, kAXDocumentAttribute)
        let url = BrowserApp.known[app.bundleID] == nil ? nil : Self.webAreaURL(in: window)
        return WindowInfo(title: title, document: document, url: url)
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let text = value as? String {
            return text
        }
        if let url = value as? URL {
            return url.absoluteString
        }
        return nil
    }

    /// The `AXURL` of the first `AXWebArea` below `window`, breadth first.
    private static func webAreaURL(in window: AXUIElement) -> String? {
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < searchLimit {
            let next = queue.removeFirst()
            visited += 1
            if string(next, kAXRoleAttribute) == "AXWebArea", let url = string(next, "AXURL") {
                return url
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(next, kAXChildrenAttribute as CFString, &children) == .success,
               let list = children as? [AXUIElement]
            {
                queue += list
            }
        }
        return nil
    }
}
