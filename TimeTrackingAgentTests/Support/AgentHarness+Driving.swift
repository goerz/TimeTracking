// AgentHarness+Driving: what the live runner forwards to the agent
// (presence events, app switches, socket lines), the fronts the tests put
// on screen, and everything the agent wrote (activity_tracking.md §2.4,
// §2.6, §4).

import Foundation
import TimeTrackingCore
@testable import TimeTrackingAgent

extension AgentHarness {
    /// The date of the fixture time.
    static let today = "2024-03-14"

    /// A date that a test names wrongly.
    struct BadDay: Error {
        var text: String
    }

    static func day(_ text: String) throws -> TrackingDay {
        guard let day = TrackingDay(text) else {
            throw BadDay(text: text)
        }
        return day
    }

    /// `2024-03-14T10:00:00`, local time in the harness's zone.
    static func instant(_ text: String) -> Date {
        ActivityTimestamp.date(text, timeZone: zone) ?? .distantPast
    }

    // MARK: Driving

    /// A presence event at the current time, as `AgentRunner` forwards it:
    /// recorded at its time, then a tick.
    func event(_ event: PresenceEvent) async {
        agent.taker.handle(event, at: clock.now)
        agent.queue.requestTick()
        await agent.queue.drain()
    }

    /// A tick now, outside the schedule, as an app switch or a hook asks
    /// for; returns the newest live Sample.
    @discardableResult
    func tick() async -> Sample? {
        agent.queue.requestTick()
        await agent.queue.drain()
        return latest
    }

    /// The newest live Sample.
    var latest: Sample? {
        samples.last { $0.source == .live }
    }

    /// One socket line through the agent's handler; returns the reply once
    /// the queue has also run the rebuild passes the request started.
    func request(_ line: String) async -> String {
        let reply = await agent.handle(line: line)
        for _ in 0 ..< 5 {
            await Task.yield()
        }
        await drain()
        return reply
    }

    /// Works for `seconds` (ticks every 30 seconds), then locks the screen.
    func workThenLock(for seconds: TimeInterval) async {
        await run(for: seconds)
        await lockAndWait()
    }

    /// Locks the screen and keeps ticking for 6 minutes: the lock ends the
    /// block once `idle_close` passed without another device's attention.
    func lockAndWait() async {
        await event(.lock)
        await run(for: 360)
    }

    /// Unlocks the screen and starts the ticks again from now.
    func unlock() async {
        presence.reading = PresenceReading()
        await event(.unlock)
    }

    // MARK: Fronts

    func textEdit(_ title: String = "Notes", document: String? = nil) {
        frontmost("com.apple.TextEdit", name: "TextEdit", title: title, document: document)
    }

    /// Safari in front on `url`, as its AppleScript reports it; `visited`
    /// adds the visit to Safari's history, so the tab is not private.
    func safari(_ url: String, title: String, visited: Bool = true) {
        frontmost("com.apple.Safari", name: "Safari")
        scripts.results["com.apple.Safari"] = .value("normal\n\(url)\n\(title)")
        if visited {
            history.safari.append((HistoryVisit(time: clock.now, browser: "safari", url: url, title: title), 0))
        }
    }

    // MARK: Terminal fixtures

    static let tmuxPanesCommand = [
        "/opt/homebrew/bin/tmux", "-S", "/private/tmp/tmux-501/default", "list-panes", "-a", "-F", TmuxSnapshot.paneFormat,
    ]
    static let weztermClientsCommand = ["/opt/homebrew/bin/wezterm", "cli", "list-clients", "--format", "json"]
    static let weztermListCommand = ["/opt/homebrew/bin/wezterm", "cli", "list", "--format", "json"]

    /// The tmux panes of the fixture with `replacements` applied.
    func editTmuxPanes(_ replacements: [(String, String)]) {
        var text = Self.fixture("tmux/list-panes.txt")
        for (old, new) in replacements {
            text = text.replacing(old, with: new)
        }
        commands.set(Self.tmuxPanesCommand, text)
    }

    /// WezTerm in front with pane `id` of the fixture focused (0: tmux
    /// session `tools`, 1: `paper`).
    func focusWezTermPane(_ id: Int) {
        let clients = Self.fixture("wezterm/list-clients.json").replacing("\"focused_pane_id\":1", with: "\"focused_pane_id\":\(id)")
        commands.set(Self.weztermClientsCommand, clients)
        wezterm()
    }

    // MARK: Output

    /// Every Sample as a fixture line.
    var sampleText: String {
        samples.map { SampleFixture.line($0, utcOffset: Self.zone.secondsFromGMT(for: $0.time)) }.joined(separator: "\n")
    }

    /// The text of the date file of `day`, `nil` without one.
    func dateFileText(_ day: String) -> String? {
        guard let date = TrackingDay(day), case let .text(text) = agent.choice.log.content(for: date) else {
            return nil
        }
        return text
    }

    /// Every date file of the block log.
    var blockLogText: String {
        agent.choice.log.days().compactMap { dateFileText($0.description) }.joined()
    }

    var currentStateText: String {
        (try? String(contentsOf: folders.currentStateURL, encoding: .utf8)) ?? ""
    }

    /// Everything the agent wrote: the Samples, the date files, and `current.json`.
    var allOutput: String {
        [sampleText, blockLogText, currentStateText].joined(separator: "\n")
    }

    /// The live Samples from `start` (seconds after the fixture time) on.
    func liveSamples(from start: TimeInterval = 0) -> [Sample] {
        samples.filter { $0.source == .live && $0.time >= time(start) }
    }

    // MARK: Files

    /// Writes `settings.toml` where the agent reads it.
    func writeSettings(_ text: String) throws {
        try text.write(to: agent.choice.settingsURL, atomically: true, encoding: .utf8)
    }

    /// Writes `blocks` as the date file of `day`, as an earlier install or
    /// another Mac left it; returns its text.
    @discardableResult
    func writeDateFile(_ day: String, _ blocks: [ActivityBlock]) throws -> String {
        let log = agent.choice.log
        try FileManager.default.createDirectory(at: log.url, withIntermediateDirectories: true)
        let text = BlockLogFile.text(of: blocks)
        let date = try Self.day(day)
        try text.write(to: log.fileURL(for: date), atomically: true, encoding: .utf8)
        return text
    }

    /// A closed block of the Mac from `start` to `end` (local times) on `item`.
    static func block(_ start: String, _ end: String, _ item: ActivityItem) -> ActivityBlock {
        let from = instant(start)
        let to = instant(end)
        return ActivityBlock(
            start: from,
            end: to,
            utcOffset: zone.secondsFromGMT(for: from),
            endReason: .idle,
            foreground: [ActivityBlockItem(device: macName, seconds: Int(to.timeIntervalSince(from)), item: item)]
        )
    }

    /// Sets the date of the agent's first start and the cutoff date, as on
    /// a Mac whose agent has run since `day`.
    func startedOn(_ day: String) throws {
        let date = try Self.day(day)
        try agent.store.setMeta(.firstStartDay, date)
        try agent.store.setMeta(.cutoffDay, date)
    }
}
