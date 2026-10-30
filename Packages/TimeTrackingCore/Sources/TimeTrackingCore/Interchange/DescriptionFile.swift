// DescriptionFile: the TOML (or JSON) file stating the clients, areas,
// colors, and standing projects a store should have (spec_automation.md §4.1).

public import Foundation
import TOMLKit

/// A parsed and validated description file.
public struct DescriptionFile: Hashable, Sendable {
    public struct ClientDescription: Hashable, Sendable {
        public var name: String
        public var areas: [AreaDescription]
    }

    public struct AreaDescription: Hashable, Sendable {
        public var name: String
        /// `#RRGGBB` in upper case.
        public var color: String
        public var projects: [String]
    }

    public var clients: [ClientDescription]

    /// Parses TOML, or JSON when the text starts with `{`; every failure is
    /// `AutomationError.invalidInput` naming the path and reason.
    public init(text: String) throws(AutomationError) {
        let object: Any
        if text.trimmed.hasPrefix("{") {
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else {
                throw .invalidInput("The description is not valid JSON.")
            }
            object = parsed
        } else {
            let table: TOMLTable
            do {
                table = try TOMLTable(string: text)
            } catch let error as TOMLParseError {
                throw .invalidInput("The description is not valid TOML: \(error.description) (\(error.source.begin.debugDescription)).")
            } catch {
                throw .invalidInput("The description is not valid TOML.")
            }
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(table.convert(to: .json).utf8)) else {
                throw .invalidInput("The description is not valid TOML.")
            }
            object = parsed
        }
        try self.init(object: object)
    }

    /// Reads the file at `url`.
    public init(contentsOf url: URL) throws(AutomationError) {
        guard let data = try? Data(contentsOf: url) else {
            throw .failure("Cannot read \(url.path).")
        }
        try self.init(text: String(decoding: data, as: UTF8.self))
    }

    private init(object: Any) throws(AutomationError) {
        guard let root = object as? [String: Any] else {
            throw .invalidInput("The description must be a table.")
        }
        guard let version = root["version"] as? Int else {
            throw .invalidInput("version: missing; the description needs version = 1.")
        }
        guard version == 1 else {
            throw .invalidInput("version: \(version) is not supported; use 1.")
        }
        let clients = root["client"] as? [Any] ?? []
        var parsed: [ClientDescription] = []
        for (index, value) in clients.enumerated() {
            try parsed.append(Self.client(value, path: "client[\(index)]"))
        }
        try Self.requireUnique(parsed.map(\.name), path: "client", kind: "client")
        for (index, client) in parsed.enumerated() {
            try Self.requireUnique(client.areas.map(\.name), path: "client[\(index)].area", kind: "area")
            try Self.requireUnique(client.areas.flatMap(\.projects), path: "client[\(index)]", kind: "project")
        }
        self.clients = parsed
    }

    private static func client(_ value: Any, path: String) throws(AutomationError) -> ClientDescription {
        guard let table = value as? [String: Any] else {
            throw .invalidInput("\(path): must be a table.")
        }
        let name = try name(table["name"], path: "\(path).name")
        guard let areas = table["area"] as? [Any], !areas.isEmpty else {
            throw .invalidInput("\(path).area: a client needs at least one area.")
        }
        var parsed: [AreaDescription] = []
        for (index, area) in areas.enumerated() {
            try parsed.append(Self.area(area, path: "\(path).area[\(index)]"))
        }
        return ClientDescription(name: name, areas: parsed)
    }

    private static func area(_ value: Any, path: String) throws(AutomationError) -> AreaDescription {
        guard let table = value as? [String: Any] else {
            throw .invalidInput("\(path): must be a table.")
        }
        let name = try name(table["name"], path: "\(path).name")
        guard let colorText = table["color"] as? String else {
            throw .invalidInput("\(path).color: missing.")
        }
        guard colorText.wholeMatch(of: /#[0-9A-Fa-f]{6}/) != nil else {
            throw .invalidInput("\(path).color: \"\(colorText)\" is not #RRGGBB.")
        }
        guard let projects = table["projects"] as? [Any] else {
            throw .invalidInput("\(path).projects: missing; use [] for none.")
        }
        var names: [String] = []
        for (index, project) in projects.enumerated() {
            let projectPath = "\(path).projects[\(index)]"
            if let table = project as? [String: Any] {
                if let key = table.keys.sorted().first(where: { $0 != "name" }) {
                    throw .invalidInput("\(projectPath): unknown key \"\(key)\"; a project table has only name.")
                }
                try names.append(Self.name(table["name"], path: "\(projectPath).name"))
            } else {
                try names.append(Self.name(project, path: projectPath))
            }
        }
        return AreaDescription(name: name, color: colorText.uppercased(), projects: names)
    }

    private static func name(_ value: Any?, path: String) throws(AutomationError) -> String {
        guard let name = (value as? String)?.trimmed, !name.isEmpty else {
            throw .invalidInput("\(path): a non-empty name is required.")
        }
        return name
    }

    private static func requireUnique(_ names: [String], path: String, kind: String) throws(AutomationError) {
        var seen: Set<String> = []
        for name in names where !seen.insert(name.folded).inserted {
            throw .invalidInput("\(path): the \(kind) name \"\(name)\" appears twice.")
        }
    }
}
