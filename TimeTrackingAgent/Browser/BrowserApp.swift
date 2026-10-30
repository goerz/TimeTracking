// BrowserApp: the browsers the agent reads and their scripts
// (spec_activity_tracking.md §3.3).

import Foundation

/// How a browser's active tab is read.
nonisolated enum BrowserScripting: Hashable, Sendable {
    /// Safari: `URL` and `name` of the current tab.
    case safari
    /// Chromium browsers: `mode` of the front window, `URL` and `title` of the active tab.
    case chromium
    /// Arc: like Chromium, with `incognito` instead of `mode`.
    case arc
    /// No scripting dictionary: `AXURL` and the title.
    case unscriptable
}

/// A browser: context name and scripting.
nonisolated struct BrowserApp: Hashable, Sendable {
    var context: String
    var scripting: BrowserScripting

    /// Safari on the Mac.
    static let safariBundleID = "com.apple.Safari"

    static let known: [String: Self] = [
        safariBundleID: Self(context: "safari", scripting: .safari),
        "com.apple.SafariTechnologyPreview": Self(context: "safari", scripting: .safari),
        "com.google.Chrome": Self(context: "chrome", scripting: .chromium),
        "com.google.Chrome.canary": Self(context: "chrome", scripting: .chromium),
        "company.thebrowser.Browser": Self(context: "arc", scripting: .arc),
        "com.brave.Browser": Self(context: "brave", scripting: .chromium),
        "com.microsoft.edgemac": Self(context: "edge", scripting: .chromium),
        "com.vivaldi.Vivaldi": Self(context: "vivaldi", scripting: .chromium),
        "org.mozilla.firefox": Self(context: "firefox", scripting: .unscriptable),
    ]

    /// The script for the active tab, answering `mode`, URL, and title on three lines.
    func script(bundleID: String) -> String? {
        switch scripting {
        case .safari:
            """
            with timeout of 1 seconds
                tell application id "\(bundleID)" to tell current tab of front window ¬
                    to return "normal" & linefeed & (URL as text) & linefeed & (name as text)
            end timeout
            """
        case .chromium:
            """
            with timeout of 1 seconds
                tell application id "\(bundleID)"
                    set theWindow to front window
                    set theTab to active tab of theWindow
                    return (mode of theWindow as text) & linefeed & (URL of theTab as text) & linefeed & (title of theTab as text)
                end tell
            end timeout
            """
        case .arc:
            """
            with timeout of 1 seconds
                tell application id "\(bundleID)"
                    set theWindow to front window
                    set theTab to active tab of theWindow
                    if incognito of theWindow then
                        set theMode to "incognito"
                    else
                        set theMode to "normal"
                    end if
                    return theMode & linefeed & (URL of theTab as text) & linefeed & (title of theTab as text)
                end tell
            end timeout
            """
        case .unscriptable:
            nil
        }
    }

    /// The Chromium profile folders' parents, relative to the home folder.
    static let chromiumProfileRoots: [(context: String, folder: String)] = [
        ("chrome", "Library/Application Support/Google/Chrome"),
        ("arc", "Library/Application Support/Arc/User Data"),
        ("brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
        ("edge", "Library/Application Support/Microsoft Edge"),
        ("vivaldi", "Library/Application Support/Vivaldi"),
    ]
}
