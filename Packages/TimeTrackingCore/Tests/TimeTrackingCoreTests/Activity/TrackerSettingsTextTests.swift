// Tests for TrackerSettingsText: adding an exclusion to settings.toml in
// place (activity_tracking.md §7.4).

import Foundation
import Testing
import TimeTrackingCore

struct TrackerSettingsTextTests {
    /// `edited` minus `inserted` at its first occurrence after `anchor`.
    private func removing(_ inserted: String, after anchor: String, from edited: String) -> String {
        guard let anchorRange = edited.range(of: anchor),
              let range = edited.range(of: inserted, range: anchorRange.upperBound ..< edited.endIndex)
        else {
            return edited
        }
        return edited.replacingCharacters(in: range, with: "")
    }

    @Test("TRK-32 an exclusion added from Activity goes into the default file's empty array and keeps every other byte")
    func emptyArrayInTheDefaultFile() throws {
        let text = TrackerSettings.defaultFileContents
        let edited = try TrackerSettingsText.appending("com.example.vault", to: "exclude_apps", in: "privacy", of: text)
        #expect(edited.contains("exclude_apps = [\"com.example.vault\"]"))
        #expect(removing("\"com.example.vault\"", after: "exclude_apps = [", from: edited) == text)
        #expect(try TrackerSettings(tomlText: edited).privacy.excludeApps == ["com.example.vault"])
    }

    @Test("TRK-32 a commented empty array keeps its comment")
    func commentedArray() throws {
        let text = "[privacy]\nexclude_domains = []   # e.g. banks\n"
        let edited = try TrackerSettingsText.appending("bank.example", to: "exclude_domains", in: "privacy", of: text)
        #expect(edited == "[privacy]\nexclude_domains = [\"bank.example\"]   # e.g. banks\n")
    }

    @Test("TRK-32 one-line arrays grow at the end, with or without a trailing comma")
    func oneLineArrays() throws {
        let text = "[privacy]\nexclude_apps = [\"a.b\", 'c.d']\nexclude_domains = [\"x.org\",]\n"
        let apps = try TrackerSettingsText.appending("e.f", to: "exclude_apps", in: "privacy", of: text)
        #expect(apps == "[privacy]\nexclude_apps = [\"a.b\", 'c.d', \"e.f\"]\nexclude_domains = [\"x.org\",]\n")
        let domains = try TrackerSettingsText.appending("y.org", to: "exclude_domains", in: "privacy", of: text)
        #expect(domains == "[privacy]\nexclude_apps = [\"a.b\", 'c.d']\nexclude_domains = [\"x.org\", \"y.org\"]\n")
    }

    @Test("TRK-32 a multi-line array gets a new line in its own indentation")
    func multiLineArray() throws {
        let text = """
        [privacy]
        exclude_apps = [
            "a.b",  # the vault
            "c.d"
        ]
        name_only_apps = []

        """
        let edited = try TrackerSettingsText.appending("e.f", to: "exclude_apps", in: "privacy", of: text)
        #expect(edited == """
        [privacy]
        exclude_apps = [
            "a.b",  # the vault
            "c.d",
            "e.f",
        ]
        name_only_apps = []

        """)
        #expect(try TrackerSettings(tomlText: edited).privacy.excludeApps == ["a.b", "c.d", "e.f"])
    }

    @Test("TRK-32 a missing key goes at the end of its table, a missing table at the end of the file")
    func missingKeyAndTable() throws {
        let text = "[privacy]\nexclude_apps = []\n\n[browser]\nsummary_domain_only = []\n"
        let key = try TrackerSettingsText.appending("work", to: "exclude_tmux_sessions", in: "privacy", of: text)
        #expect(key == "[privacy]\nexclude_apps = []\nexclude_tmux_sessions = [\"work\"]\n\n[browser]\nsummary_domain_only = []\n")
        let table = try TrackerSettingsText.appending("work", to: "exclude_tmux_sessions", in: "privacy", of: "[files]\nroots = []\n")
        #expect(table == "[files]\nroots = []\n\n[privacy]\nexclude_tmux_sessions = [\"work\"]\n")
        let empty = try TrackerSettingsText.appending("work", to: "exclude_tmux_sessions", in: "privacy", of: "")
        #expect(empty == "[privacy]\nexclude_tmux_sessions = [\"work\"]\n")
    }

    @Test("TRK-32 a value already listed changes nothing; quotes and backslashes are escaped; a key that is no setting throws")
    func duplicatesEscapesAndErrors() throws {
        let text = "[privacy]\nexclude_title_keywords = [\"Secret\"]\n"
        #expect(try TrackerSettingsText.appending("Secret", to: "exclude_title_keywords", in: "privacy", of: text) == text)
        let edited = try TrackerSettingsText.appending("a \"b\" \\c", to: "exclude_title_keywords", in: "privacy", of: text)
        #expect(try TrackerSettings(tomlText: edited).privacy.excludeTitleKeywords == ["Secret", "a \"b\" \\c"])
        #expect(throws: ActivityError.self) {
            try TrackerSettingsText.appending("x", to: "no_such_key", in: "privacy", of: text)
        }
        #expect(throws: ActivityError.self) {
            try TrackerSettingsText.appending("x", to: "idle_close", in: "blocks", of: "[blocks]\nidle_close = \"5m\"\n")
        }
        #expect(throws: ActivityError.self) {
            try TrackerSettingsText.appending("x", to: "exclude_apps", in: "privacy", of: "[privacy\n")
        }
    }

    @Test("TRK-32 the errors shown under the settings file name the line, the setting, or the expected list")
    func errorMessages() {
        func message(_ text: String) -> String {
            do {
                _ = try TrackerSettings(tomlText: text)
                return ""
            } catch {
                return error.localizedDescription
            }
        }
        let syntax = message("[privacy]\nexclude_apps = [\"a\"\n")
        #expect(syntax.hasPrefix("The settings file has an error on line 2: "))
        #expect(syntax.hasSuffix(". Fix it in the editor."))
        #expect(!syntax.contains("TOML"))
        let duration = message("[presence]\nidle_after = \"soon\"\n")
        #expect(duration.hasPrefix("In the settings file, "))
        #expect(duration.contains("idle_after can't be used: \"soon\" is not a duration such as \"30s\", \"5m\", or \"3h\""))
        let list = message("[privacy]\nexclude_apps = \"x\"\n")
        #expect(list == "In the settings file, exclude_apps under [privacy] must be a list, like [\"com.example.app\"].")
    }

    @Test("TRK-32 a header-like line inside a multi-line string or array is not a table")
    func headersOnlyAtTopLevel() throws {
        let text = """
        [browser.categories]
        research = [
          "arxiv.org",
        ]

        [privacy]
        exclude_domains = []
        """
        let edited = try TrackerSettingsText.appending("z.org", to: "exclude_domains", in: "privacy", of: text)
        #expect(try TrackerSettings(tomlText: edited).privacy.excludeDomains == ["z.org"])
        #expect(try TrackerSettings(tomlText: edited).browser.categories["research"] == ["arxiv.org"])
    }
}
