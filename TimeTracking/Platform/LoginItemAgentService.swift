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
