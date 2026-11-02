// Entities to and from sync records; field names are those of spec_data_and_sync.md §1.

import Foundation
import GRDB

extension SyncRecord {
    static func make(_ type: SyncRecordType, _ name: String, _ fields: [String: SyncValue?]) -> Self {
        Self(ref: SyncRecordRef(type, name), fields: fields.compactMapValues { $0 })
    }

    func text(_ key: String) -> String? {
        fields[key]?.string
    }

    func instant(_ key: String) -> Date? {
        fields[key]?.date.map { Time.whole($0) }
    }

    /// The record's `modifiedAt`, from its millisecond field.
    var modifiedAt: Date {
        Time.date(millis: modifiedMillis)
    }

    func flag(_ key: String) -> Bool {
        (fields[key]?.int ?? 0) != 0
    }

    func id<Entity>(_ key: String) -> Identifier<Entity>? {
        text(key).flatMap { Identifier($0) }
    }
}

private func value(_ string: String?) -> SyncValue? {
    string.map { .string($0) }
}

private func value(_ date: Date?) -> SyncValue? {
    date.map { .date($0) }
}

private func value(_ bool: Bool) -> SyncValue {
    .int(bool ? 1 : 0)
}

extension Client {
    var syncRecord: SyncRecord {
        .make(
            .client,
            id.rawValue,
            ["name": value(name), "createdAt": value(createdAt), "modifiedAt": value(modifiedAt), "deletedAt": value(deletedAt)]
        )
    }

    init?(record: SyncRecord) {
        guard let id: ClientID = Identifier(record.ref.name), let name = record.text("name") else {
            return nil
        }
        self.init(
            id: id,
            name: name,
            createdAt: record.instant("createdAt") ?? .distantPast,
            modifiedAt: record.modifiedAt,
            deletedAt: record.instant("deletedAt")
        )
    }
}

extension Area {
    var syncRecord: SyncRecord {
        .make(.area, id.rawValue, [
            "clientID": value(clientID.rawValue), "name": value(name), "general": value(isGeneral), "color": value(color),
            "sortOrder": .int(Int64(sortOrder)), "retired": value(isRetired), "createdAt": value(createdAt),
            "modifiedAt": value(modifiedAt), "deletedAt": value(deletedAt),
        ])
    }

    init?(record: SyncRecord) {
        guard let id: AreaID = Identifier(record.ref.name), let clientID: ClientID = record.id("clientID"),
              let name = record.text("name")
        else {
            return nil
        }
        self.init(
            id: id,
            clientID: clientID,
            name: name,
            isGeneral: record.flag("general"),
            color: record.text("color") ?? "#808080",
            sortOrder: Int(record.fields["sortOrder"]?.int ?? 0),
            isRetired: record.flag("retired"),
            createdAt: record.instant("createdAt") ?? .distantPast,
            modifiedAt: record.modifiedAt,
            deletedAt: record.instant("deletedAt")
        )
    }
}

extension Project {
    var syncRecord: SyncRecord {
        .make(.project, id.rawValue, [
            "areaID": value(areaID.rawValue), "name": value(name), "archived": value(isArchived), "archivedAt": value(archivedAt),
            "createdAt": value(createdAt), "modifiedAt": value(modifiedAt), "deletedAt": value(deletedAt),
        ])
    }

    init?(record: SyncRecord) {
        guard let id: ProjectID = Identifier(record.ref.name), let areaID: AreaID = record.id("areaID"),
              let name = record.text("name")
        else {
            return nil
        }
        self.init(
            id: id,
            areaID: areaID,
            name: name,
            isArchived: record.flag("archived"),
            archivedAt: record.instant("archivedAt"),
            createdAt: record.instant("createdAt") ?? .distantPast,
            modifiedAt: record.modifiedAt,
            deletedAt: record.instant("deletedAt")
        )
    }
}

extension TimeEntry {
    var syncRecord: SyncRecord {
        .make(.timeEntry, id.rawValue, [
            "projectID": value(projectID?.rawValue), "task": value(task), "start": value(start), "end": value(end),
            "timeZone": value(timeZone), "deviceID": value(deviceID.rawValue), "splitRootID": value(splitRootID?.rawValue),
            "createdAt": value(createdAt), "modifiedAt": value(modifiedAt), "deletedAt": value(deletedAt),
        ])
    }

    init?(record: SyncRecord) {
        guard let id: EntryID = Identifier(record.ref.name), let start = record.instant("start"),
              let deviceID: DeviceID = record.id("deviceID")
        else {
            return nil
        }
        self.init(
            id: id,
            projectID: record.id("projectID"),
            task: record.text("task") ?? "",
            start: start,
            end: record.instant("end"),
            timeZone: record.text("timeZone") ?? TimeZone.current.identifier,
            deviceID: deviceID,
            splitRootID: record.id("splitRootID"),
            createdAt: record.instant("createdAt") ?? start,
            modifiedAt: record.modifiedAt,
            deletedAt: record.instant("deletedAt")
        )
    }
}

extension Device {
    var syncRecord: SyncRecord {
        .make(.device, id.rawValue, [
            "name": value(name), "platform": value(platform.rawValue), "lastSeenAt": value(lastSeenAt),
            "widgetPushToken": value(widgetPushToken), "createdAt": value(createdAt), "modifiedAt": value(modifiedAt),
        ])
    }

    init?(record: SyncRecord) {
        guard let id: DeviceID = Identifier(record.ref.name), let name = record.text("name") else {
            return nil
        }
        self.init(
            id: id,
            name: name,
            platform: DevicePlatform(rawValue: record.text("platform") ?? "") ?? .mac,
            lastSeenAt: record.instant("lastSeenAt") ?? .distantPast,
            widgetPushToken: record.text("widgetPushToken"),
            createdAt: record.instant("createdAt") ?? .distantPast,
            modifiedAt: record.modifiedAt
        )
    }
}

extension HealthPeriod {
    var syncRecord: SyncRecord {
        .make(.healthPeriod, id.rawValue, [
            "kind": value(kind.rawValue), "start": value(start), "end": value(end), "activity": value(activity),
            "distance": distance.map { .int(Int64($0)) }, "createdAt": value(createdAt),
            "modifiedAt": value(modifiedAt), "deletedAt": value(deletedAt),
        ])
    }

    init?(record: SyncRecord) {
        guard let id: HealthPeriodID = Identifier(record.ref.name),
              let kind = Kind(rawValue: record.text("kind") ?? ""),
              let start = record.instant("start"),
              let end = record.instant("end")
        else {
            return nil
        }
        self.init(
            id: id,
            kind: kind,
            start: start,
            end: end,
            activity: record.text("activity"),
            distance: record.fields["distance"]?.int.map { Int($0) },
            createdAt: record.instant("createdAt") ?? start,
            modifiedAt: record.modifiedAt,
            deletedAt: record.instant("deletedAt")
        )
    }
}
