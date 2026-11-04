// TimeStore+ExternalChanges: other processes' commits, signaled by the
// Darwin notification `<APP_ID>.changed` (spec_data_and_sync.md §2.2, §7).

import Foundation
import GRDB

extension TimeStore {
    func listenForExternalChanges() {
        guard let notifier, externalChanges == nil else {
            return
        }
        dataVersion = currentDataVersion()
        knownSettings = settingRows()
        let stream = notifier.notifications()
        externalChanges = Task { [weak self] in
            for await _ in stream {
                await self?.notified()
            }
        }
    }

    /// A change notification: observers re-read when another connection
    /// committed since the last one. Without a writer every notification counts.
    private func notified() {
        let version = currentDataVersion()
        guard version == nil || version != dataVersion else {
            return
        }
        dataVersion = version
        externalChange()
    }

    /// Another process committed: observers re-read, settings report the
    /// keys whose rows changed.
    func externalChange() {
        broadcaster.yield(.entries([]))
        let running = try? runningEntry()
        lastRunning = running
        broadcaster.yield(.runningEntry(running))
        broadcaster.yield(.structure)
        broadcaster.yield(.health)
        broadcaster.yield(.liveState)
        let settings = settingRows()
        let changed = Set(settings.keys).union(knownSettings.keys).filter { settings[$0] != knownSettings[$0] }
        knownSettings = settings
        if !changed.isEmpty {
            broadcaster.yield(.settings(changed))
        }
    }

    /// `PRAGMA data_version` of the writer connection, or `nil` without one.
    private func currentDataVersion() -> Int? {
        try? writer?.writeWithoutTransaction { database in
            try Int.fetchOne(database, sql: "PRAGMA data_version")
        }
    }

    /// Every setting row's value and deletion time, by key.
    func settingRows() -> [String: String] {
        let rows = try? read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT key, coalesce(value, '') || '|' || coalesce(deleted_at, '') AS state FROM setting"
            )
        }
        var result: [String: String] = [:]
        for row in rows ?? [] {
            result[row["key"]] = row["state"]
        }
        return result
    }
}
