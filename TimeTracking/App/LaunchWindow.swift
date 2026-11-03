// LaunchWindow: the windows the app opens at launch (spec_timer.md §1.3, §8.1).

import Foundation

/// A window a launch can open: the "At launch, show" setting, and the
/// entries of the record of open windows (`OpenWindowsRecord`).
enum LaunchWindow: String, Codable, Sendable, CaseIterable {
    case mainWindow = "main"
    case miniTimer = "mini"

    /// The windows a launch opens, in this order: for a login-item launch
    /// the windows open when the app last quit (none leaves only the menu
    /// bar item), for any other launch the "At launch, show" window. A
    /// login launch follows the session (what was open at logout or
    /// shutdown comes back), a launch by hand follows the setting. The
    /// order of `allCases` opens the main window first, so the small Mini
    /// Timer ends up in front of it.
    static func opened(setting: Self, launchedAsLoginItem: Bool, openAtQuit: Set<Self>) -> [Self] {
        launchedAsLoginItem ? allCases.filter(openAtQuit.contains) : [setting]
    }
}
