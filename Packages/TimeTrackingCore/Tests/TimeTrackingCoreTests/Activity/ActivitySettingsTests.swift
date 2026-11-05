// Tests for TrackerSettings, TrackerDuration, and ExclusionRules
// (activity_tracking.md §7.1, §7.2).

import Foundation
import Testing
import TimeTrackingCore

struct ActivitySettingsTests {
    @Test func theDefaultFileDecodesToTheDefaults() throws {
        let settings = try TrackerSettings(tomlText: TrackerSettings.defaultFileContents)
        #expect(settings == TrackerSettings.defaults)
        #expect(settings.presence.idleAfter == 120)
        #expect(settings.presence.passiveLimit == TimeInterval(3 * 3600))
        #expect(settings.blocks.maxBlock == 90 * 60)
        #expect(settings.blocks.minBlock == 10 * 60)
        #expect(settings.blocks.summaryLines == 6)
        #expect(settings.terminal.titlePatterns == ["nvim": "^nvim (/.+)$"])
        #expect(settings.privacy.privateAgentPaths == ["~"])
        #expect(settings.browser.categories["code"]?.first == "github.com")
        #expect(try TrackerSettings(tomlText: "") == TrackerSettings.defaults)
    }

    @Test("TRK-56 a key the tracker doesn't know is ignored, and the default file holds no removed setting")
    func unknownKeysAreIgnored() throws {
        let text = """
        [terminal]
        agent_processes = ["claude", "codex", "aider"]

        [privacy]
        record_commands = false
        exclude_apps = ["com.example.vault"]
        """
        var expected = TrackerSettings.defaults
        expected.privacy.excludeApps = ["com.example.vault"]
        #expect(try TrackerSettings(tomlText: text) == expected)
        #expect(!TrackerSettings.defaultFileContents.contains("agent_processes"))
        #expect(!TrackerSettings.defaultFileContents.contains("record_commands"))
    }

    @Test func aPartialFileKeepsTheOtherDefaults() throws {
        let text = """
        [blocks]
        idle_close = "10m"
        split_threshold = 1

        [privacy]
        exclude_apps = ["com.example.vault"]
        """
        let settings = try TrackerSettings(tomlText: text)
        #expect(settings.blocks.idleClose == 600)
        #expect(settings.blocks.splitThreshold == 1)
        #expect(settings.blocks.splitAfter == 1200)
        #expect(settings.privacy.excludeApps == ["com.example.vault"])
        #expect(settings.privacy.nameOnlyApps == ["com.1password.1password"])
        #expect(settings.presence == TrackerPresenceSettings())
    }

    @Test func anInvalidDurationIsAnError() {
        #expect(throws: ActivityError.self) {
            try TrackerSettings(tomlText: "[presence]\nidle_after = \"soon\"\n")
        }
    }

    @Test func durationsParseAndFormat() {
        #expect(TrackerDuration.parse("30s") == 30)
        #expect(TrackerDuration.parse("5m") == 300)
        #expect(TrackerDuration.parse("3h") == TimeInterval(3 * 3600))
        #expect(TrackerDuration.parse("1h30m") == 5400)
        #expect(TrackerDuration.parse("45") == 45)
        #expect(TrackerDuration.parse("5x") == nil)
        #expect(TrackerDuration.parse("m") == nil)
        #expect(TrackerDuration.parse("5m3") == nil)
        #expect(TrackerDuration.format(3 * 3600) == "3h")
        #expect(TrackerDuration.format(5400) == "90m")
        #expect(TrackerDuration.format(30) == "30s")
    }

    @Test func theEncoderRoundTrips() throws {
        var settings = TrackerSettings.defaults
        settings.blocks.idleClose = 420
        settings.privacy.excludeDomains = ["bank.example"]
        let text = try settings.tomlText()
        #expect(text.contains("idle_close = '7m'") || text.contains("idle_close = \"7m\""))
        #expect(try TrackerSettings(tomlText: text) == settings)
    }

    @Test func aMissingFileGivesTheDefaults() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let url = folder.url.appending(path: "missing.toml")
        #expect(try TrackerSettings(contentsOf: url) == TrackerSettings.defaults)
    }

    @Test func exclusionsMatchCaseInsensitively() {
        var privacy = TrackerPrivacySettings()
        privacy.excludePaths = ["~/Documents/Medical"]
        privacy.excludeKeywords = ["sparsebundle"]
        privacy.excludeTmuxSessions = ["Private"]
        privacy.excludeApps = ["com.example.Vault"]
        privacy.excludeDomains = ["bank.example"]
        privacy.privateDomains = ["health.example"]
        privacy.excludeTitleKeywords = ["Secret"]
        let rules = ExclusionRules(privacy: privacy, homeDirectory: "/Users/example")

        #expect(rules.excludesPath("/users/example/documents/medical"))
        #expect(rules.excludesPath("~/Documents/Medical/scan.pdf"))
        #expect(rules.excludesPath("file:///Users/example/Documents/Medical/a%20b.pdf"))
        #expect(!rules.excludesPath("~/Documents/MedicalNotes"))
        #expect(rules.excludesPath("/Volumes/SparseBundle-2024/file"))
        #expect(!rules.excludesPath("/Volumes/Backup/file"))
        #expect(rules.isPrivateAgentPath("/Users/example/"))
        #expect(!rules.isPrivateAgentPath("~/Documents"))
        #expect(rules.excludesTmuxSession("private"))
        #expect(rules.excludesContext("tmux:PRIVATE", bundleIdentifier: nil))
        #expect(rules.excludesContext("vault", bundleIdentifier: "COM.EXAMPLE.VAULT"))
        #expect(!rules.excludesContext("safari", bundleIdentifier: "com.apple.Safari"))
        #expect(rules.isNameOnlyApp("com.1Password.1password"))
        #expect(rules.excludesDomain("online.Bank.example"))
        #expect(rules.excludesDomain("https://bank.example/login"))
        #expect(!rules.excludesDomain("notbank.example"))
        #expect(rules.isPrivateDomain("health.example."))
        #expect(rules.excludesTitle("My secret plan"))
        #expect(!ExclusionRules.empty.excludesPath("/anything"))
    }
}
