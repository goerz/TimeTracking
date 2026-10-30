// StoreFixture: the files `Fixtures/Store/<name>.json` (spec_architecture.md §3.4).

public import Foundation

/// Locates and loads the store fixtures for `-UITesting YES -Fixture <name>`,
/// tests, and previews.
public enum StoreFixture {
    /// Folders searched for `<name>.json`: `TIMETRACKING_FIXTURES` (a
    /// `Fixtures/Store` folder), the bundle's `Fixtures/Store` resources,
    /// and the source tree this library was built from.
    public static func searchFolders(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var folders: [URL] = []
        if let path = environment["TIMETRACKING_FIXTURES"], !path.isEmpty {
            folders.append(URL(filePath: path, directoryHint: .isDirectory))
        }
        if let resources = Bundle.main.resourceURL {
            folders.append(resources.appending(path: "Fixtures/Store", directoryHint: .isDirectory))
        }
        folders.append(sourceFixtures)
        return folders
    }

    /// `Fixtures/Store` of the repository, from this file's path.
    public static var sourceFixtures: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../../../Fixtures/Store", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    /// The file of fixture `name`, if found.
    public static func url(named name: String) -> URL? {
        searchFolders()
            .map { $0.appending(path: "\(name).json", directoryHint: .notDirectory) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Imports fixture `name` (with settings) into `store`, rebased so its
    /// wall-clock times are the same in `timeZone` as in the fixture's zone:
    /// the `running` fixture runs for 25 minutes at 10:00 local time anywhere.
    public static func load(named name: String, into store: TimeStore, timeZone: TimeZone = .current) async throws {
        guard let url = url(named: name) else {
            throw StoreError.invalidDocument(path: "$", reason: "no fixture named \(name)")
        }
        let data = try rebased(Data(contentsOf: url), to: timeZone)
        _ = try await store.importDocument(data, options: ImportOptions(includeSettings: true))
    }

    /// The document with every entry moved to the same local times in
    /// `timeZone` and that zone as its `timeZone`.
    public static func rebased(_ data: Data, to timeZone: TimeZone) throws -> Data {
        guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var entries = document["entries"] as? [[String: Any]]
        else {
            return data
        }
        for index in entries.indices {
            let source = (entries[index]["timeZone"] as? String).flatMap { TimeZone(identifier: $0) } ?? timeZone
            func move(_ key: String) {
                guard let text = entries[index][key] as? String, let date = FixtureShift.date(text) else {
                    return
                }
                let moved = FixtureShift.wallClock(date, from: source, to: timeZone, addingDays: 0)
                entries[index][key] = moved.map { TimeStore.rfc3339($0) } ?? text
            }
            move("start")
            move("end")
            entries[index]["timeZone"] = timeZone.identifier
        }
        document["entries"] = entries
        return try JSONSerialization.data(withJSONObject: document)
    }
}
