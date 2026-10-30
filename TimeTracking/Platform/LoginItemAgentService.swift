// LoginItemAgentService: the agent's registration through SMAppService
// (spec_architecture.md §1.4).

import Foundation
import os
import ServiceManagement
import TimeTrackingCore

/// Registers `Contents/Library/LaunchAgents/<APP_ID>.agent.plist`.
@MainActor
final class LoginItemAgentService: AgentService {
    private let service: SMAppService
    private let label: String

    init(identity: AppIdentity) {
        self.service = SMAppService.agent(plistName: identity.agentPlistName)
        self.label = identity.agentBundleID
    }

    var registration: AgentRegistration {
        Self.registration(of: service.status)
    }

    static func registration(of status: SMAppService.Status) -> AgentRegistration {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() async throws {
        try await service.unregister()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// `launchctl kickstart -k gui/<uid>/<label>`: launchd stops the agent
    /// and starts it at once. A new Full Disk Access grant reached the
    /// running agent only after this (spec_activity_tracking.md §5).
    func restart() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            Logging.logger(category: "LoginItem").error("restart: launchctl exit status \(status, privacy: .public)")
            throw AgentServiceError.restartFailed(status: status)
        }
    }

    /// `--unregister`, run by the agent's own `--unregister`: only this
    /// bundle's `SMAppService` sees its `Contents/Library/LaunchAgents` plist.
    /// Not being registered is the goal, so that is success; returns 1 when
    /// the registration is still there afterwards.
    static func unregisterAgent(identity: AppIdentity? = .main) -> Int32 {
        guard let identity else {
            FileHandle.standardError.write(Data("no identity in the Info.plist\n".utf8))
            return 1
        }
        let service = SMAppService.agent(plistName: identity.agentPlistName)
        guard [.enabled, .requiresApproval].contains(service.status) else {
            return 0
        }
        do {
            try service.unregister()
        } catch {
            Logging.logger(category: "LoginItem").info("unregister: \(error.localizedDescription, privacy: .public)")
        }
        return [.enabled, .requiresApproval].contains(service.status) ? 1 : 0
    }
}

/// Errors of the login item services.
enum AgentServiceError: LocalizedError, Equatable {
    case restartFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .restartFailed: "The tracker could not be restarted. Disable and enable it to try again."
        }
    }
}
