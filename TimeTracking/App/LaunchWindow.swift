// LaunchWindow: the window the app shows at launch (spec_timer.md §1.3, §8.1).

import Foundation

/// The "At launch, show" setting.
enum LaunchWindow: String, Codable, Sendable, CaseIterable {
    case mainWindow = "main"
    case miniTimer = "mini"

    /// The window a launch shows: none for a login-item launch unless
    /// "Also show it at login" is on.
    static func shown(setting: Self, launchedAsLoginItem: Bool, showAtLogin: Bool) -> Self? {
        launchedAsLoginItem && !showAtLogin ? nil : setting
    }
}
