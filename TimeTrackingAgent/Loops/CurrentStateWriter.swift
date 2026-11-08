// CurrentStateWriter: current.json, written by the tick with the
// foreground, presence, and health, and by the rebuild with the open block
// (activity_tracking.md §4.4).

import Foundation
import os
import TimeTrackingCore

/// Holds both parts of `current.json` and rewrites the whole file when
/// either changes. What it writes is filtered by the exclusions and
/// redacted, as everything that leaves the agent.
@MainActor
final class CurrentStateWriter {
    let url: URL
    private(set) var block: ActivityBlock?
    private var foreground: ActivityItem?
    private var presence: TrackerPresence?
    private var health: TrackerHealth?
    private let logger = Logging.logger(category: "Agent")

    /// A writer of `url`, seeded with the open block the file holds, so a
    /// restart doesn't drop it until the rebuild loop reaches today.
    init(url: URL) {
        self.url = url
        self.block = (try? Data(contentsOf: url)).flatMap { try? TrackerState.parse($0) }?.block
    }

    /// The tick's part: the latest live Sample's foreground, the presence, and the health.
    func update(foreground: ActivityItem?, presence: TrackerPresence, health: TrackerHealth, rules: SampleRules, redactor: Redactor) {
        self.foreground = foreground.flatMap(rules.exclusions.applied(to:)).map(redactor.redacted)
        self.presence = presence
        self.health = health
        write(zone: rules.zone)
    }

    /// The rebuild's part: the open block, already filtered and redacted.
    func update(block: ActivityBlock?, zone: TimeZone) {
        guard block != self.block else {
            return
        }
        self.block = block
        write(zone: zone)
    }

    private func write(zone: TimeZone) {
        guard let presence, let health else {
            return
        }
        let state = TrackerState(block: block, foreground: foreground, presence: presence, health: health)
        do {
            try ActivityFile.write(Data(state.jsonText(timeZone: zone).utf8), to: url)
        } catch {
            logger.error("current.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
