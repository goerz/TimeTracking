// Logging: one unified-log subsystem per process, one category per module
// (spec_architecture.md §4.1).

import Foundation
public import os

/// Factory for `os.Logger` instances.
///
/// The subsystem is the process's bundle identifier; a tool without one uses
/// `<APP_ID>.<process name>`, or the process name outside a build.
public enum Logging {
    /// The subsystem of every logger in this process.
    public static let subsystem: String = {
        if let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty {
            return identifier
        }
        let process = ProcessInfo.processInfo.processName
        if let identity = AppIdentity.main {
            return "\(identity.appID).\(process)"
        }
        return process
    }()

    /// A logger for `category`, which names the module.
    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
