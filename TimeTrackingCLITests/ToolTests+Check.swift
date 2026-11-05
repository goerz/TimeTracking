// The timetracking tool as a subprocess: the description file and check
// (automation.md §4, §9 items 19 to 23).

import Foundation
import Testing

/// Description files for the fixture store.
enum ToolCheckTests {
    /// A description the fixture store matches.
    static let matching = """
    version = 1

    [[client]]
    name = "University"

      [[client.area]]
      name = "University"
      color = "#6C757D"
      projects = []

      [[client.area]]
      name = "Research"
      color = "#0a9396"
      projects = ["Noise paper"]

      [[client.area]]
      name = "Teaching"
      color = "#EE9B00"
      projects = ["Admin", { name = "Grading" }]

    [[client]]
    name = "Personal"

      [[client.area]]
      name = "Personal"
      color = "#6C757D"
      projects = ["Émile notes"]

    [[client]]
    name = "Side business"

      [[client.area]]
      name = "Side business"
      color = "#AE2012"
      projects = ["Admin"]
    """

    /// `matching` with a wrong Research color, a missing and an archived
    /// standing project.
    static let threeDifferences = matching
        .replacingOccurrences(
            of: "color = \"#0a9396\"\n  projects = [\"Noise paper\"]",
            with: "color = \"#123456\"\n  projects = [\"Noise paper\", \"Grant renewal\", \"Old paper\"]"
        )
}

extension ToolTests {
    @Test("AUTO-19 check on a matching file prints nothing and exits 0")
    func checkMatching() throws {
        let fixture = try ToolFixture()
        let file = try fixture.write(ToolCheckTests.matching, named: "match.toml")
        let result = try fixture.run(["check", file])
        #expect(result.status == 0, "\(result.standardOutput) \(result.standardError)")
        #expect(result.standardOutput.isEmpty)
        let json = try fixture.run(["check", file, "--json"])
        #expect((json.json["inconsistencies"] as? [Any])?.isEmpty == true)
    }

    @Test("AUTO-20 a wrong color, a missing and an archived standing project print three lines in rule order and exit 6")
    func checkDifferences() throws {
        let fixture = try ToolFixture()
        let file = try fixture.write(ToolCheckTests.threeDifferences, named: "diff.toml")
        let result = try fixture.run(["check", file])
        #expect(result.status == 6)
        #expect(result.lines == [
            "color mismatch: University / Research is #0A9396, expected #123456",
            "archived project: University / Research / Old paper",
            "missing project: University / Research / Grant renewal",
        ])
        let json = try fixture.run(["check", file, "--json"])
        #expect(json.status == 6)
        let kinds = (json.json["inconsistencies"] as? [[String: Any]])?.compactMap { $0["kind"] as? String }
        #expect(kinds == ["color-mismatch", "archived-project", "missing-project"])
        let first = (json.json["inconsistencies"] as? [[String: Any]])?.first
        #expect(first?["rule"] as? Int == 3)
        #expect(first?["actual"] as? String == "#0A9396")
        #expect(first?["expected"] as? String == "#123456")
    }

    @Test("AUTO-21 a file without version, with color teal, or with an extra project key exits 7; { name } equals a plain name")
    func checkValidation() throws {
        let fixture = try ToolFixture()
        let invalid = [
            ToolCheckTests.matching.replacingOccurrences(of: "version = 1\n", with: ""),
            ToolCheckTests.matching.replacingOccurrences(of: "#EE9B00", with: "teal"),
            ToolCheckTests.matching.replacingOccurrences(of: "{ name = \"Grading\" }", with: "{ name = \"Grading\", area = \"x\" }"),
            ToolCheckTests.matching.replacingOccurrences(of: "version = 1", with: "version = 2"),
            "version = 1\n[[client]]\nname = \"A\"\n",
            "not toml at all = = =",
        ]
        for (index, text) in invalid.enumerated() {
            let file = try fixture.write(text, named: "invalid\(index).toml")
            let result = try fixture.run(["check", file])
            #expect(result.status == 7, "case \(index): \(result.standardError)")
            #expect(result.standardOutput.isEmpty)
        }
        let plain = try fixture.write(
            ToolCheckTests.matching.replacingOccurrences(of: "{ name = \"Grading\" }", with: "\"Grading\""),
            named: "plain.toml"
        )
        #expect(try fixture.run(["check", plain]).standardOutput == fixture.run([
            "check",
            fixture.write(ToolCheckTests.matching, named: "m.toml"),
        ]).standardOutput)
        let json = """
        {"version": 1, "client": [{"name": "University",
          "area": [{"name": "Research", "color": "#0A9396", "projects": [{"name": "Noise paper"}]}]}]}
        """
        let jsonResult = try fixture.run(["check", fixture.write(json, named: "description.json"), "--client", "University"])
        #expect(jsonResult.lines == ["unlisted area: University / Teaching (active projects: Admin, Grading)"])
    }

    @Test("AUTO-22 an active project in an area absent from the file gives one unlisted-area line; an empty unlisted area none")
    func checkUnlistedArea() throws {
        let fixture = try ToolFixture()
        // Garden (Personal) has no projects and is not listed: no line.
        let withoutTeaching = ToolCheckTests.matching.replacingOccurrences(
            of: "  [[client.area]]\n  name = \"Teaching\"\n  color = \"#EE9B00\"\n  projects = [\"Admin\", { name = \"Grading\" }]\n",
            with: ""
        )
        let result = try fixture.run(["check", fixture.write(withoutTeaching, named: "u.toml")])
        #expect(result.status == 6)
        #expect(result.lines == ["unlisted area: University / Teaching (active projects: Admin, Grading)"])
        let withoutSide = ToolCheckTests.matching.components(separatedBy: "[[client]]\nname = \"Side business\"")[0]
        let clientResult = try fixture.run(["check", fixture.write(withoutSide, named: "c.toml")])
        #expect(clientResult.lines == ["unlisted client: Side business (active projects: 1)"])
    }

    @Test("AUTO-23 check --fix repairs the client, color, and archived project, then reports only the wrong area and exits 6")
    func checkFix() throws {
        let fixture = try ToolFixture()
        // Missing client Lab (general area only), Research recolored,
        // Old paper archived, Grading listed in Research but in Teaching.
        let text = ToolCheckTests.matching
            .replacingOccurrences(
                of: "color = \"#0a9396\"\n  projects = [\"Noise paper\"]",
                with: "color = \"#3D5A80\"\n  projects = [\"Noise paper\", \"Old paper\", \"Grading\"]"
            )
            .replacingOccurrences(of: "projects = [\"Admin\", { name = \"Grading\" }]", with: "projects = [\"Admin\"]")
            + "\n\n[[client]]\nname = \"Lab\"\n\n  [[client.area]]\n  name = \"Lab\"\n  color = \"#112233\"\n  projects = []\n"
        let file = try fixture.write(text, named: "fix.toml")
        let projectsBefore = try fixture.run(["projects", "--all", "--json"]).json["projects"] as? [[String: Any]] ?? []
        let result = try fixture.run(["check", file, "--fix"])
        #expect(result.status == 6)
        #expect(result.lines == [
            "created client: Lab",
            "recolored area: University / Research from #0A9396 to #3D5A80",
            "unarchived project: University / Research / Old paper",
            "wrong area: University / Grading is in Teaching, expected Research",
        ])
        let again = try fixture.run(["check", file])
        #expect(again.lines == ["wrong area: University / Grading is in Teaching, expected Research"])
        let projectsAfter = try fixture.run(["projects", "--all", "--json"]).json["projects"] as? [[String: Any]] ?? []
        #expect(projectsAfter.count == projectsBefore.count)
        let grading = projectsAfter.first { $0["name"] as? String == "Grading" }
        #expect((grading?["area"] as? [String: Any])?["name"] as? String == "Teaching")
        #expect(projectsAfter.allSatisfy { $0["state"] as? String == "active" })
        let lab = try fixture.run(["areas", "--client", "Lab", "--json"]).json["areas"] as? [[String: Any]]
        #expect(lab?.first?["color"] as? String == "#112233")
        let json = try fixture.run(["check", file, "--fix", "--json"])
        #expect((json.json["actions"] as? [Any])?.isEmpty == true)
        #expect((json.json["inconsistencies"] as? [[String: Any]])?.first?["kind"] as? String == "wrong-area")
    }
}
