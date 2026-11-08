// LocalHost: this Mac's names, read from the system configuration without
// a DNS lookup (activity_tracking.md §3.1, §5).

import Foundation
import SystemConfiguration

/// The Mac's computer name and the host names a terminal may show for it.
/// `Host.current().names` resolves them through DNS and can block for
/// half a minute, which would hold up the agent's start and its exit.
nonisolated enum LocalHost {
    /// The computer name of Sharing settings ("Alex's MacBook Pro").
    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ProcessInfo.processInfo.hostName
    }

    /// The local host name with and without `.local`, the host name, and
    /// the computer name, in lower case.
    static var names: Set<String> {
        var names: Set<String> = [ProcessInfo.processInfo.hostName, computerName]
        if let local = SCDynamicStoreCopyLocalHostName(nil) as String? {
            names.insert(local)
            names.insert(local + ".local")
        }
        return Set(names.filter { !$0.isEmpty }.map { $0.lowercased() })
    }
}
