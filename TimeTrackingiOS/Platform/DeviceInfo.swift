// DeviceInfo: the device's name and kind, the pasteboard, and the system
// settings URL, which SwiftUI does not provide (spec_ios.md §2.6, §8, §11).

import UIKit

/// The device's name and kind.
enum DeviceInfo {
    /// The system's name for this device (prefills onboarding).
    static var systemName: String {
        UIDevice.current.name
    }

    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// The app's page in the Settings app.
    static var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}

/// `-UITesting YES` runs without animations (spec_architecture.md §3.3).
enum UIViewAnimations {
    static func disable() {
        UIView.setAnimationsEnabled(false)
    }
}

/// "Copy Task".
enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
