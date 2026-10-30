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

    init(identity: AppIdentity) {
        self.service = SMAppService.agent(plistName: identity.agentPlistName)
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

/// "Open at login" for the app itself (`SMAppService.mainApp`).
@MainActor
enum OpenAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logging.logger(category: "LoginItem").error("Open at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
