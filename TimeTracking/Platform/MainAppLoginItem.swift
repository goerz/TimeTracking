// MainAppLoginItem: "Open at login" through SMAppService.mainApp
// (spec_timer_window.md §8.1, §8.2).

import ServiceManagement
import TimeTrackingCore

/// "Open at login" for the app itself (`SMAppService.mainApp`).
@MainActor
final class MainAppLoginItem: AppLoginItemService {
    var registration: AgentRegistration {
        LoginItemAgentService.registration(of: SMAppService.mainApp.status)
    }

    func setOpensAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
