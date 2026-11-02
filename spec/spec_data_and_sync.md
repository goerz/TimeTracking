# Spec: Shared Library, Data Model, and Sync

The shared library (`TimeTrackingCore`) is linked by every executable: the Mac app, the iPhone and iPad app, the widget and intent extensions, the command-line tool, and the tracker agent for the parts it shares. It owns the entities and their invariants, the store, iCloud sync, the live-update path to the iPhone and iPad widgets, JSON export and import, the reader for the tracker's logs, and the queries behind every view and script. User interfaces hold views and view state only.

## 1. Entities

Identifiers are lowercase UUIDs: version 4 for new records, version 5 for midnight-split pieces (1.5). Times are instants with second precision. Name uniqueness everywhere compares case- and diacritic-insensitively ("folded"). Every entity carries the bookkeeping fields of 1.7.

### 1.1 Client

| Field | Type | Meaning |
|---|---|---|
| id | UUID | |
| name | String | Non-empty after trimming; unique among live clients. |

Clients are listed alphabetically by folded name. A client has exactly one general area (1.2), created in the same transaction. A client is retired when none of its areas holds an active (live, unarchived) project; `Client.isRetired` is derived at query time, never stored. A client can be deleted only when it has no other area and no live project; deletion tombstones it and its general area together.

### 1.2 Area

| Field | Type | Meaning |
|---|---|---|
| id | UUID | |
| clientID | UUID | Never changes. |
| name | String | Non-empty; unique within the client; only the general area may carry the client's name. |
| general | Bool | True for the client's general area (Swift `isGeneral`); fixed at creation. |
| color | String | `#RRGGBB`, sRGB, stored uppercase. |
| sortOrder | Int | Position within the client; the general area is always 0. |
| retired | Bool | Hidden from pickers and project creation; history keeps reporting. |

Renaming a client renames its general area in the same transaction. The general area cannot be renamed separately, reordered, retired, or deleted (`StoreError.generalArea`); its color can change. Retiring an area with an active project fails (`activeProjects`); restoring a project of a retired area un-retires it; creating a project in a retired area fails (`areaRetired`). An area can be deleted only when no live project references it.

The store accepts `#RRGGBB` in either case and stores it uppercase; anything else fails with `invalidColor`. A project's color is its area's; projects and entries store none.

Default color of a new area (including a new client's general area): take the HSB hues (whole degrees) of all live areas with saturation at least 0.1. With none, use hue 210. Otherwise take the midpoint, rounded down, of the largest circular gap between sorted hues (on equal gaps, the one starting at the smallest hue). The color is that hue at saturation 0.65 and brightness 0.80, rounded per sRGB channel. Hues 0 and 120 give 240.

The type `AreaColor` implements every color derivation: relative luminance, the contrast-safe text color (black or white, whichever has the higher WCAG contrast), and the tints and per-project lightness steps whose parameters the Projects and Reports specs define.

### 1.3 Project

| Field | Type | Meaning |
|---|---|---|
| id | UUID | |
| areaID | UUID | May change, also to another client's area. |
| name | String | Non-empty; unique among the client's live projects. |
| archived | Bool | Hidden from pickers and autocompletion; entries kept; restorable. |
| archivedAt | Instant? | Set when archived, cleared when restored. |

Moving a project into a client that has a live project of that name fails with `duplicateName`. Starting or continuing an entry on an archived project fails with `projectArchived`; a running entry whose project is archived elsewhere keeps running. A project with live entries cannot be deleted (`referenced`); `merge(project:into:)` moves all entries to another project and tombstones the first.

### 1.4 Time entry

| Field | Type | Meaning |
|---|---|---|
| id | UUID | |
| projectID | UUID? | `nil` is "no project". |
| task | String | Free-text description, trimmed, may be empty. |
| start | Instant | |
| end | Instant? | `nil` while running; otherwise `end >= start`. |
| timeZone | String | IANA zone of the creating device; decides the entry's day and midnights (section 8). |
| deviceID | UUID | Creating device (1.8). |
| splitRootID | UUID? | For a split piece, the id of the chain's first piece. |

Duration is `end - start` (`now - start` while running), never stored or rounded. Invariants:

1. At most one live entry runs across all devices (3.3).
2. No live entry crosses a midnight of its `timeZone` (1.5); ending exactly at midnight is fine.
3. No library write sets `start` or `end` after the writing device's current time (`inFuture`). Synced records are not checked; a running entry starting more than 5 minutes in the future is a consistency issue.
4. Overlaps are tolerated; callers check with `overlaps(for:excluding:)`.
5. A reference to a project not yet received is kept, shown as "unknown project", and reported by `consistencyIssues()`.

### 1.5 The midnight split and the chain

Midnight is `Calendar.startOfDay` in the entry's `timeZone` (correct for zones whose DST change falls at midnight). An entry whose interval (up to now while running) contains midnights M1 < … < Mk after `start` becomes k + 1 pieces. The original keeps its id and ends at M1; the piece starting at Mi ends at the next midnight, at the original end, or keeps running. Each piece copies `projectID`, `task`, `timeZone`, and `deviceID`, has `createdAt = Mi`, `splitRootID = R` (the original's `splitRootID ?? id`), and id UUIDv5 (RFC 9562) with namespace R and name `split:YYYY-MM-DD`, the local date of Mi. Devices therefore produce identical pieces however they split.

The invariant pass splits a running entry when a writing process sees a midnight pass: at each local midnight of the entry's zone, on opening the store, on wake, on a clock or significant time change, and on every write. Creating, editing, moving, or importing across midnight splits in the same transaction; the write returns all pieces, the given id first. Pieces are ordinary entries afterwards and are never joined. A derived id that exists as a tombstone stays deleted and that part of the interval is dropped. Until a writer splits a running entry, read-only openers attribute it whole to its start day.

An entry's chain is the live entries with the same root (`splitRootID ?? id`); its chain start is their earliest `start`. Running-entry displays (Timer label, menu bar, widgets) count elapsed time from the chain start (`chainStart(of:)`, 7.2).

### 1.6 Settings

Synced settings are records; device settings live in the App Group's `UserDefaults` suite. Other specs register their own keys through `SyncedSettingKey<T>` and `DeviceSettingKey<T>`. Shared or owned here:

| Key | Scope | Type | Default | Owner |
|---|---|---|---|---|
| `pomodoro.focusMinutes` | synced | Int | 25 | Timer |
| `pomodoro.breakMinutes` | synced | Int | 5 | Timer |
| `pinnedProjectIDs` | synced | [UUID] | [] | iOS widgets |
| `activity.contextColors` | synced | [String: Int] (context to hue index) | {} | Activity |
| `calendar.timeBlockCalendarID` | synced | String? | nil | Calendar |
| `calendar.timeBlockCalendarTitle` | synced | String? | nil ("Time Blocks") | Calendar |
| `calendar.showSleep` | synced | Bool | false | Calendar; the iPhone imports sleep while on (1.9) |
| `calendar.showWorkouts` | synced | Bool | false | Calendar; the iPhone imports workouts while on (1.9) |
| `calendar.sleepAreaID`, `calendar.workoutAreaID` | synced | AreaID? | nil | Calendar settings; Reports count the kind in that area (7.3) |
| `calendar.healthImport` | synced | HealthImportStatus? | nil | Written by the iPhone's import: device name, time, kinds read (1.9); the Calendar settings show it |
| `calendar.snapMinutes` | synced | Int | 5 | Calendar |
| `calendar.shownCalendars` | synced | [(account, calendar)] titles | [] | Calendar |
| `deviceID` | device | UUID | created on first launch | this spec |
| `pomodoro.sounds` | device | Bool | true | Timer |
| `idle.thresholdMinutes` | device | Int | 10 | Timer |

Shortcuts, menu bar display, window frames, and Pomodoro state are device settings of their owner specs. Synced settings merge per key by last writer, except `activity.contextColors`, which merges as the union, the smaller index winning for a context assigned differently. A new context takes the hue index used by the fewest contexts, lowest on ties.

### 1.7 Bookkeeping

Every record has `createdAt` (a split piece's: its midnight), `modifiedAt` (the last local change in milliseconds by the writing device's clock, which drives conflict resolution, 3.2), and `deletedAt`, set by every deletion. Tombstones are invisible unless `includeDeleted` is requested and are hard-deleted locally and in CloudKit after 180 days. Deleting anything a live record references fails with `referenced`.

### 1.8 Device

| Field | Type | Meaning |
|---|---|---|
| id | UUID | The `deviceID` device setting. |
| name | String | User-visible device name. |
| platform | String | `mac`, `iphone`, or `ipad`. |
| lastSeenAt | Instant | Updated at most hourly while the app runs. |
| widgetPushToken | String? | iPhone and iPad: the widget extension's WidgetKit push token, hex; `nil` without installed widgets. |

Entries show "created on iPhone" through this record. Devices are never deleted automatically.

### 1.9 Health period

| Field | Type | Meaning |
|---|---|---|
| id | UUID | |
| kind | String | `sleep` or `workout`. |
| start, end | Instant | Whole seconds. |

Sleep and workouts from Apple Health, for the Calendar ([spec_calendar.md](spec_calendar.md) §3.1). HealthKit exists only on the iPhone and iPad, so the iPhone imports and the store syncs the periods to the Mac and iPad; only the iPhone writes them ([spec_ios.md](spec_ios.md) §7 item 6). A sleep period is the asleep samples of any stage (unspecified, core, deep, REM) merged where they overlap or lie at most 30 minutes apart, plus each in-bed period that holds no asleep sample (a night recorded by the iPhone's sleep schedule alone); a workout period is a workout from start to end, overlapping workouts (one workout recorded by two apps) merged.

An import of one kind covers the 60 days before now the first time, afterwards from 3 days before the previous import (samples a watch syncs late), and reads samples from a day earlier still, so a period that began before the range is whole. `replaceHealthPeriods(kind, from:, with:)` then makes the live periods of that kind starting at or after the range's start equal the imported ones: a period with the same start and end keeps its record, the others become tombstones, and new ones are created. Periods starting earlier are left alone. Health periods are not part of the JSON export.

After an import in which at least one kind succeeded, the iPhone writes the synced setting `calendar.healthImport`: its device name, the time in whole seconds, and the kinds read, in the order sleep, workout. It skips the write when the stored status has the same device and kinds and is less than an hour old, so frequent wakes don't each sync a record. `HealthImportStatus.summary(_:shown:found:)` turns it, the kinds shown, and the kinds with live periods (`healthKinds()`) into the Calendar settings' status line ([spec_calendar.md](spec_calendar.md) §6).

## 2. Persistence

### 2.1 Store and schema

One SQLite database in WAL mode, through GRDB.swift, at `<App Group container>/Library/Application Support/TimeTracking/store.sqlite` (identifiers in spec_architecture.md §1.5; Debug builds have their own). The tracker agent does not open it. Timestamps are Unix seconds except `modified_at` (milliseconds); booleans 0/1.

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);  -- schema_version '2', store_id

CREATE TABLE client (id TEXT PRIMARY KEY, name TEXT NOT NULL,
  created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB);

CREATE TABLE area (id TEXT PRIMARY KEY, client_id TEXT NOT NULL, name TEXT NOT NULL,
  general INTEGER NOT NULL DEFAULT 0, color TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0, retired INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB);

CREATE TABLE project (id TEXT PRIMARY KEY, area_id TEXT NOT NULL, name TEXT NOT NULL,
  archived INTEGER NOT NULL DEFAULT 0, archived_at INTEGER,
  created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB);

CREATE TABLE time_entry (id TEXT PRIMARY KEY, project_id TEXT, task TEXT NOT NULL DEFAULT '',
  task_key TEXT NOT NULL DEFAULT '',          -- task, trimmed and folded
  start INTEGER NOT NULL, "end" INTEGER,       -- NULL while running
  day TEXT NOT NULL,                           -- 'YYYY-MM-DD', local date of start in time_zone
  time_zone TEXT NOT NULL, device_id TEXT NOT NULL, split_root_id TEXT,
  created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB);

CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL,  -- JSON
  modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB);

CREATE TABLE device (id TEXT PRIMARY KEY, name TEXT NOT NULL, platform TEXT NOT NULL,
  last_seen_at INTEGER NOT NULL, widget_push_token TEXT,
  created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, ck_system_fields BLOB);

CREATE TABLE live_state (id INTEGER PRIMARY KEY CHECK (id = 1),   -- section 4
  running TEXT, changed_at INTEGER, activity TEXT NOT NULL DEFAULT '{}', ck_system_fields BLOB);

CREATE TABLE health_period (id TEXT PRIMARY KEY, kind TEXT NOT NULL,   -- 1.9; schema version 2
  start INTEGER NOT NULL, "end" INTEGER NOT NULL,
  created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB);

CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, record_type TEXT NOT NULL,
  record_id TEXT NOT NULL, queued_at INTEGER NOT NULL);
CREATE TABLE sync_state (key TEXT PRIMARY KEY, value BLOB NOT NULL);  -- CKSyncEngine state

CREATE VIEW entries AS
  SELECT e.id, e.start, e."end", e."end" - e.start AS seconds, e.day, e.task,
         p.id AS project_id, p.name AS project, a.id AS area_id, a.name AS area, a.color,
         c.id AS client_id, c.name AS client, e.device_id, e.time_zone
  FROM time_entry e LEFT JOIN project p ON p.id = e.project_id
       LEFT JOIN area a ON a.id = p.area_id LEFT JOIN client c ON c.id = a.client_id
  WHERE e.deleted_at IS NULL;
```

Partial indexes cover live entries by `start`, by `day`, the running entry, (`project_id`, `task_key`, `start`), and `split_root_id`. The library computes `day` and `task_key` on every write. No foreign keys are declared, since records sync in any order. Migrations run forward on open and only add columns and tables (version 2 adds `health_period` and its index on live starts); a newer schema than the library knows is refused.

Scripts open the file read-only (`?mode=ro`) and may rely on the `entries` view and the `client`, `area`, `project`, and `setting` tables, whose columns are stable within a major schema version (columns may be added). Everything else is private; scripts write through the command-line tool.

### 2.2 Processes and change notification

Writers are the app (Mac and iOS) and, on the Mac, the command-line tool; iOS widget and control buttons write through intents that run in the app process. WAL with a 5 second busy timeout serializes them. Each write transaction runs the invariant pass (3.3), appends one `outbox` row per changed record, and after commit posts the Darwin notification `<APP_ID>.changed`, the only cross-process change signal. Only the app runs the sync engine and drains the outbox: on the Mac within a second, on iOS at the app's next run. After applying remote changes on iOS the library reloads all widget timelines.

## 3. Synchronization

### 3.1 CloudKit layout and engine

The private database of `iCloud.<APP_ID>` (development environment, spec_architecture.md) holds the zone `TimeTracking` with the record types `Client`, `Area`, `Project`, `TimeEntry`, `Setting`, `Device`, `HealthPeriod`, and `LiveState`, and the zone `ActivityEvents` with `DeviceEvent` (section 6). Record names are the UUIDs (for `Setting` the key, for `LiveState` the fixed name `LiveState`); fields use the camelCase names of section 1; references are `String` UUIDs, so nothing cascades. Record types and fields are only ever added.

The `CKSyncEngine` runs in the app process with automatic sync and a database subscription for silent pushes; the library's `SyncCoordinator` is its delegate:

1. It drains `outbox` into pending changes on every store change and calls `sendChanges()` at once after a change to the running entry or `LiveState`.
2. A batch containing a `LiveState` save is atomic by zone and includes the entry records that produced it.
3. A `serverRecordChanged` conflict merges (3.2, 4.1) and re-queues; an `unknownItem` error re-saves without system fields; a `zoneNotFound` error recreates the zone and re-queues every live record and tombstone.
4. Fetched changes are applied in one transaction followed by the invariant pass. A remote hard deletion of a live local record acts as a tombstone at `now`.
5. A switch to another iCloud account resets the store to empty after confirmation; with no account the store works locally.

CloudKit throttles and delays silent pushes, so the apps also fetch on their own. The Mac app fetches whenever it becomes active and 30 seconds after its last fetch while it runs, one fetch at a time; iOS fetches at every foreground, before acting on a widget or control button, and in its refresh task (iOS spec §6.1, §7).

A start or stop on one online device appears in the app on another within 5 seconds in the common case and 30 seconds at worst before `SyncStatus` shows waiting. The `SyncStatus` values are `idle`, `sending(count)`, `fetching`, `waitingForNetwork`, `noAccount`, or `error(message)`. Writes never wait for the network. A fresh device fetches the whole zone behind a progress indicator before showing data.

### 3.2 Conflict resolution

The copy with the later `modifiedAt` wins entirely; on a tie the greater `id`, then `deviceID` (`Setting` and `Device` by record name). Deletion is an ordinary modification, so a later edit resurrects a deleted record. The only field-level merges are `activity.contextColors` (1.6) and `LiveState` (4.1). The same project name created on two devices yields two projects, reported for "Merge into". A project added to an area whose client was deleted elsewhere is reported as orphaned for reassignment, never deleted. Daily maintenance hard-deletes tombstones older than 180 days everywhere.

### 3.3 The invariant pass

After every local write and every applied remote batch, in the same transaction, as a pure function of the store and the current time:

1. Split every live entry that crosses a midnight of its zone (1.5).
2. If several entries run, order them by chain start, then root id. The last keeps running. For each other one, with T the next one's chain start: entries of its chain with `start >= T` are tombstoned, and the one with `start < T` that runs or ends after T gets `end = T`.
3. Count for `consistencyIssues()`: a running entry starting more than 5 minutes ahead of this device's clock, dangling references, and duplicate names.

Changed rows get `modifiedAt = now` and are queued; the pass never reopens an entry. Example: A starts X at 23:00 offline and B starts Y at 23:30, and both split at midnight while apart; every device ends with X from 23:00 to 23:30, Y from 23:30 to midnight, Y's continuation running, and X's continuation tombstoned.

Every change the pass or conflict resolution makes to an entry is an `EntryAdjustment` (entry, reason, before, after, causing record and device, time), kept in a ring of 100 and the `os` log, with reason `splitAtMidnight`, `stoppedByLaterStart`, `removedByLaterStart`, `replacedByRemoteEdit`, `deletedRemotely`, or `restoredRemotely`. Adjustments other than `splitAtMidnight` to entries created on this device are emitted as `.adjusted` (7.4) ("Stopped at 10:14 because an entry started on MacBook").

The `SyncTransport` protocol has a `CloudKitTransport` and an `InMemoryTransport` (simulated server with change tags, delays, partitions, and `serverRecordChanged`); tests run several stores against it with a `ManualClock`. The `CloudKitTransport` has an integration test against the Debug container (`make test-sync`).

## 4. Live updates

The running entry and each Mac's current activity reach iPhone and iPad widgets within seconds through the `LiveState` record, widget push tokens on `Device` records, and WidgetKit pushes sent by the Mac app. There is no server.

### 4.1 The `LiveState` record

One record named `LiveState` in zone `TimeTracking`, mirrored in the `live_state` row.

| Field | Type | Meaning |
|---|---|---|
| running | String (JSON) or absent | `{"entryID", "projectID", "task", "projectName", "clientName", "areaColor", "chainStart"}`; project fields null for no project; `chainStart` RFC 3339 UTC. Absent when nothing runs. |
| changedAt | Date | Last change of the running part, milliseconds. |
| activity | String (JSON) | Map from a Mac's device id to `{"device", "primary", "groupKey", "presence", "since", "agentRunning", "lastTick", "health", "updatedAt"}`. |

The activity fields come from that Mac's `current.json` (tracker spec §4.4): the device name, `primary` as `[context, subject, detail]` or null, the open block's `g` or null, the presence state and its `since`, whether the tracker is running (tracker spec §4.4), the last tick, `health` as the ids of sources whose status is not `active`, and the time of this write.

On a conflict the running part with the later `changedAt` wins, and per Mac the activity entry with the later `updatedAt` wins; entries present on one side only are kept.

### 4.2 Writers

Running part, any writing process: after each write transaction the library computes the snapshot and, if it differs from the local row, writes it with `changedAt = now` and queues `LiveState` in the same transaction. Applying a remote `LiveState` updates the local row first, so the receiver writes nothing.

Activity part, Mac app only: `LiveStatePublisher` (macOS) watches the local `current.json` and writes this Mac's entry. Changes of `presence`, `agentRunning`, or `health` are written at once; changes of `primary` or `groupKey` at most once per 30 seconds, a change inside the window being written at its end with the then current values. A `lastTick` change alone writes nothing; `agentRunning` is re-evaluated every 30 seconds.

### 4.3 Widget pushes

The iOS app stores its widget push token with `setWidgetPushToken(_:)` on its `Device` record (iOS spec §4, item 1, says when). The library's `WidgetPushSender` (macOS, injectable transport and clock) runs only in the Mac app and decides when and to whom; credentials and the request are in spec_architecture.md §2.4. It pushes to every `Device` with platform `iphone` or `ipad` and a token:

- after the engine confirms the Mac's own `LiveState` save;
- after the Mac applies a fetched `LiveState` whose running part changed (another Mac's activity change sends nothing; that Mac sends its own).

Running-part pushes go out at once; activity-only pushes at most once per 60 seconds per token, a later one being sent at the window's end. With two Macs, duplicates only cause an extra reload. The `WidgetPushStatus` is `noKey` (no pushes), `idle(lastSentAt)`, or `failing(message)`.

The call `LiveStateReader.fetch(timeout:) async throws -> LiveState` fetches the record from CloudKit without the sync engine, for the widget timeline providers (iOS spec §4, item 2). With the Mac awake and online, a stop on any device reaches a Home Screen widget in about 5 seconds; otherwise widgets follow CloudKit pushes, app runs, and scheduled reloads.

## 5. JSON export and import

### 5.1 Export

The command `timetracking export` and an App Intent write the whole store as one document, the backup and interchange format:

```json
{
  "format": 1,
  "generatedAt": "2026-10-29T14:03:11Z",
  "storeID": "…",
  "clients":  [{"id": "…", "name": "University", "createdAt": "…"}],
  "areas":    [{"id": "…", "clientID": "…", "name": "Research", "general": false, "color": "#2E8BC0", "sortOrder": 1, "retired": false, "createdAt": "…"}],
  "projects": [{"id": "…", "areaID": "…", "name": "Noise paper", "archived": false, "archivedAt": null, "createdAt": "…"}],
  "entries":  [{"id": "…", "projectID": "…", "task": "Clarify noise model", "start": "2026-10-29T08:00:00Z", "end": "2026-10-29T09:30:00Z", "timeZone": "America/New_York", "deviceID": "…", "splitRootID": null}],
  "settings": {"pomodoro.focusMinutes": 25, "pinnedProjectIDs": []},
  "devices":  [{"id": "…", "name": "MacBook", "platform": "mac"}]
}
```

Timestamps are RFC 3339 UTC; a running entry has `"end": null`. Only synced settings are included; devices carry no push tokens. With `includeDeleted`, tombstones appear with `deletedAt`. Clients and projects are sorted by name, areas by client, `sortOrder`, and name, entries by `start`, ties by `id`; object keys are sorted, so two exports of unchanged data differ only in `generatedAt`.

### 5.2 Import

The call `importDocument(_:options:)` reads the same format and upserts by id; the command `timetracking import` calls it, and external converters write this format (spec_automation.md).

Required: `format` 1; clients `id`, `name`; areas `id`, `clientID`, `name`, `color`; projects `id`, `areaID`, `name`; entries `id`, `start`, `end`. Missing optional fields default to `sortOrder` 0, false flags, null `archivedAt`, `projectID`, and `splitRootID`, empty `task`, `createdAt` now, `timeZone` `options.defaultTimeZone` (else the device's zone), and `deviceID` the importing device. The import ignores `generatedAt`, `storeID`, and `devices`, and applies `settings` only with `options.includeSettings`.

In one transaction:

1. Validate everything: format, required fields, UUIDs, colors, `end >= start`, nothing in the future, at most one running entry, resolvable references, and the name rules on the resulting store. The first failure throws `invalidDocument(path:reason:)` with a JSON path such as `entries[1041].end`, and nothing is written.
2. Give a client without a general area one with id UUIDv5(namespace: client id, name: `general-area`), the client's name, and the default color.
3. Upsert by id: insert new rows, replace changed live rows, skip equal ones, and skip local tombstones (`skippedDeleted`). Document records that carry `deletedAt` are ignored, so an import never deletes. Written rows get `modifiedAt = now`.
4. Run the invariant pass.

The `ImportReport` counts `created`, `updated`, `unchanged`, and `skippedDeleted` per entity, plus `splitPieces` and adjustments. With `options.dryRun` the transaction is rolled back.

## 6. Activity logs

The tracker spec defines the formats; this section fixes locations and the reader.

| Artifact | Location | Writer | Readers |
|---|---|---|---|
| `Activity/blocks/YYYY-MM.jsonl` | iCloud Drive container `iCloud.<APP_ID>`, outside `Documents/`; local fallback `<App Group>/Library/Application Support/TimeTracking/Activity/` | Tracker agent, which replaces a day's lines when it forms the day again (or the Mac app's copy, tracker spec §4.1) | Mac app, iPhone, iPad, scripts |
| `Activity/settings.toml` | Same folder | The Mac app's Tracker pane only | Tracker agent, iOS app (exclusions) |
| `Activity/current.json` | Mac, local folder | Tracker agent, every tick | Mac app, including `LiveStatePublisher` |
| `Activity/detail/YYYY-MM-DD.jsonl` | Mac, local folder | Tracker agent | `detail(for:)` on the recording Mac; scripts |
| `DeviceEvent` records, zone `ActivityEvents` | CloudKit | iOS app | Tracker agent, through `DeviceEventSource` |
| `Activity/events.jsonl` | iOS, App Group | iOS extensions and app, append | iOS app (flushes to CloudKit, truncates) |

The iPhone and iPad learn the Mac's current activity only from `LiveState`. The `DeviceEvent` fields are `deviceID`, `time`, `source` (`ladder`, `focus`, `intent`, `webext`, `app`), `label`, `kind` (tracker spec), optional JSON `payload`. The record name `<deviceID>-<time in ms>-<sequence>` makes an interrupted flush resume without duplicates. The agent merges events into the user's timeline (tracker spec §2.8) and deletes records older than 90 days.

```swift
public struct ActivityItem { var context, subject, detail: String; var seconds: Int; var device: String }
public struct ActivityDeviceTime { var name: String; var seconds: Int; var isRecordingMac: Bool }   // isIOSDevice: neither the Mac nor "remote"
public struct ActivityBlock: Identifiable {
    var id: String                              // the start, RFC 3339 with offset
    var start, end: Date; var activeSeconds: Int
    var devices: [ActivityDeviceTime]           // most time first
    var reconstructedSeconds: Int               // isMostlyReconstructed: more than half of activeSeconds
    var groupKey: String; var groupShare: Double
    var items, background: [ActivityItem]
    var isOpen: Bool                            // today's provisional block (Mac only)
    func restricted(to: Set<String>) -> Self?   // the part on those devices: their items and time
}
public protocol ActivityReading: Sendable {
    func blocks(in: DateInterval, devices: Set<String>?) async throws -> [ActivityBlock]   // exclusions applied; a device filter keeps each block's part on them
    func detail(for: ActivityBlock.ID) async throws -> ActivityBlockDetail?                // URLs, files, presence; nil off the recording Mac
    func currentState() async -> TrackerState?                                              // parsed current.json, Mac only
    func aggregate(in: DateInterval, by: ActivityGroupKey, device: String?) async throws -> [ActivityAggregate]   // context, subject, groupKey, hourOfDay, day
    func bundleIdentifier(forContext: String) -> String?
    var exclusions: ExclusionRules { get }
    var changes: AsyncStream<ActivityChange> { get }
}
public protocol DeviceEventSink { func append(_: DeviceEvent) throws; func flush() async throws }   // iOS; flush in the app only
public protocol DeviceEventSource {                                                            // Mac agent only
    func events(since: ChangeToken?) async throws -> ([DeviceEvent], ChangeToken)
    func purge(before: Date) async throws
    var changes: AsyncStream<Void> { get }
}
```

The `FileActivityStore` reads JSON Lines lazily from a shared and a local folder, skips headers, counts malformed lines for health, converts local times with the latest header's `tz` (whose `dev` marks the recording Mac's time), and indexes month files, invalidating on change; `detail(for:)` reads the day file named by the id's date. On iOS it downloads the months in view and watches with `NSMetadataQuery`. The tracker closes blocks at midnight, so the reader never splits them.

## 7. Query layer

Queries are SQL behind `async` APIs on the store's serial executor, returning value types with typed ids.

### 7.1 Writing

```swift
public protocol TimeStoreWriting: Sendable {
    func start(projectID: ProjectID?, task: String, at: Date) async throws -> TimeEntry   // stops the running entry at `at`
    func stop(at: Date) async throws -> TimeEntry?
    func `continue`(_: EntryID, at: Date) async throws -> TimeEntry
    func create(_: EntryDraft) async throws -> [TimeEntry]                     // split pieces, given id first
    func update(_: EntryID, _: EntryChange) async throws -> [TimeEntry]        // project, task, start, end
    func move(_: EntryID, by: TimeInterval) async throws -> [TimeEntry]
    func split(_: EntryID, at: Date) async throws -> (TimeEntry, TimeEntry)    // user split, random id
    func delete(_: [EntryID]) async throws
    func restore(_: [EntryID]) async throws
    func createClient(name: String, generalAreaColor: String?) async throws -> (Client, Area)
    func updateClient(_: ClientID, name: String) async throws
    func deleteClient(_: ClientID) async throws
    func createArea(_: AreaDraft) async throws -> Area
    func updateArea(_: AreaID, _: AreaChange) async throws                     // name, color, sortOrder, retired
    func deleteArea(_: AreaID) async throws
    func createProject(_: ProjectDraft) async throws -> Project
    func updateProject(_: ProjectID, _: ProjectChange) async throws            // name, areaID
    func archive(_: ProjectID) async throws
    func restoreProject(_: ProjectID) async throws
    func merge(project: ProjectID, into: ProjectID) async throws
    func deleteProject(_: ProjectID) async throws
    func set<T: Codable>(_: SyncedSettingKey<T>, _: T) async throws
    func setWidgetPushToken(_: String?) async throws
    func replaceHealthPeriods(_: HealthPeriod.Kind, from: Date, with: [DateInterval]) async throws -> Int   // 1.9
    func importDocument(_: Data, options: ImportOptions) async throws -> ImportReport
    func transaction<R>(_: (TimeStoreWriting) async throws -> R) async throws -> R   // one transaction, one pass
}
```

A `nil` color means the default rule. Every write validates, writes, runs the pass, queues, and notifies. The `StoreError` cases are `emptyName`, `duplicateName`, `projectArchived`, `areaRetired`, `generalArea`, `activeProjects`, `invalidColor`, `endBeforeStart`, `inFuture`, `referenced`, `unknownID`, `retentionExpired`, `invalidDocument`.

### 7.2 Reading

```swift
public protocol TimeStoreReading: Sendable {
    func runningEntry() async throws -> TimeEntry?
    func chainStart(of: EntryID) async throws -> Date
    func entry(_: EntryID) async throws -> TimeEntry?
    func entries(in: DateInterval, includeDeleted: Bool) async throws -> [TimeEntry]   // intersecting
    func entries(on: TrackingDay) async throws -> [TimeEntry]
    func days(ending: TrackingDay, count: Int) async throws -> [DayGroup]               // newest first
    func recentEntries(before: Date?, limit: Int) async throws -> [TimeEntry]
    func lastStoppedEntry(excluding: EntryID?) async throws -> TimeEntry?
    func healthPeriods(in: DateInterval) async throws -> [HealthPeriod]                 // live, intersecting, by start
    func recentProjects(limit: Int) async throws -> [ProjectID]                         // by latest entry start
    func overlaps(for: EntryDraft, excluding: EntryID?) async throws -> [TimeEntry]
    func overlappingEntries(in: DateInterval) async throws -> [(TimeEntry, TimeEntry)]
    func distinctTasks(projectID: ProjectID?, prefix: String, limit: Int) async throws -> [TaskSuggestion]
    func projectsByTask(matching: String, since: Date) async throws -> [ProjectID]      // picker task matching (90 days)
    func recentCombinations(limit: Int) async throws -> [(ProjectID?, String)]
    func consistencyIssues() async throws -> [ConsistencyIssue]
}
public protocol StructureReading: Sendable {
    func clients(includeRetired: Bool) async throws -> [Client]                         // alphabetical
    func areas(of: ClientID?, includeRetired: Bool) async throws -> [Area]
    func projects(filter: ProjectFilter) async throws -> [ProjectRow]                   // with client, area, color, entry count, last used, total
    func project(_: ProjectID) async throws -> Project?
    func projectTree(includeArchived: Bool) async throws -> [ClientNode]                // client > area > projects
    func searchProjects(_: String, limit: Int) async throws -> [ProjectRow]             // fuzzy on project, area, client names
    func devices() async throws -> [Device]
}
```

A `DayGroup` holds a day's entries, `totalSeconds` (the running entry counted to the query time), and `includesRunning`. The query `distinctTasks` matches the folded prefix against `task_key`, skips archived projects, returns each task once by most recent use (recent tasks for an empty prefix), and with `projectID == nil` searches entries without a project.

### 7.3 Reports

```swift
public enum Granularity { case day, week, month, year, total }
public enum GroupKey { case client, area, project, task, day }
public struct EntryFilter { var clients: Set<ClientID>?; var areas: Set<AreaID>?; var projects: Set<ProjectID>?; var taskContains: String?; var includeNoProject, includeArchived: Bool }
public struct ReportQuery { var days: ClosedRange<TrackingDay>; var groupBy: [GroupKey]; var granularity: Granularity; var filter: EntryFilter }
public struct ReportNode { var key: GroupKeyValue; var seconds, entryCount: Int; var buckets: [TrackingPeriod: Int]; var children: [ReportNode] }
public protocol Reporting: Sendable {
    func report(_: ReportQuery) async throws -> ReportNode                                  // root = grand total
    func series(_: ReportQuery) async throws -> [(TrackingPeriod, [GroupKeyValue: Int])]   // stacked bars
    func entries(matching: ReportQuery) async throws -> [TimeEntry]
}
```

A report counts each entry whose `day` lies in the range whole in its day, the running one up to the query time, so the Timer list and Reports agree. Client and area grouping use the project's current area. A health kind that is shown and mapped to a live area by its setting adds one row per day it touches, its part of that day, under the fixed project id `kind.reportProjectID` named "Sleep" or "Workouts" in that area, with an empty task; the filters treat it as a project of that area with no record ([spec_reports.md](spec_reports.md) §1.1). `entries(matching:)` returns entries only. A query's `includeHealth` (default on; the tool's `report` turns it on only with `--health`) leaves the health rows out when off, and its optional `bounds`, instants inside the days, keep only the entries starting inside them and cut health time at them (the tool's instant ranges, spec_automation.md §3.2). The `ReportCSVWriter` writes the Breakdown and Entries CSV whose columns spec_automation.md defines.

### 7.4 Observation

```swift
public enum StoreChange { case entries(Set<EntryID>), runningEntry(TimeEntry?), structure, settings(Set<String>), liveState, health, sync(SyncStatus), adjusted([EntryAdjustment]) }
public protocol StoreObserving { var changes: AsyncStream<StoreChange> { get }; func recentAdjustments(limit: Int) async -> [EntryAdjustment] }
```

Same-process changes arrive after commit; other processes' changes arrive through the Darwin notification as `.entries([])`, `.runningEntry`, `.structure`, and `.health`, and observers re-read.

### 7.5 Performance

On the `large` fixture (9.1), on a current Mac and iPhone, checked by a separate test plan:

| Operation | Target |
|---|---|
| `runningEntry()` | under 1 ms |
| Single-entry write | under 5 ms |
| `entries(on:)`, `days(ending:count: 7)`, `entries(in:)` for 7 days | under 10 ms |
| `distinctTasks` with a 2-character prefix | under 20 ms |
| `blocks(in:)` for 7 days, month files cached; opening the store | under 50 ms |
| `report` over one year, four levels, by day | under 100 ms |
| `report` over ten years, four levels, by month | under 300 ms |
| Export of the whole store; `importDocument` of 300,000 entries | under 10 s; under 60 s |

## 8. Days, weeks, and time zones

Days start at midnight, local time; there is no setting. An entry's day is the date of its `start` in its own `timeZone`, and the entry lies wholly within it; after travel, entries keep their recorded day. Weeks run Monday to Sunday with ISO 8601 numbers.

```swift
public struct TrackingDay: Hashable, Comparable, Codable { var year, month, day: Int }   // "YYYY-MM-DD"
public struct TrackingCalendar {
    init(timeZone: TimeZone)
    func day(containing: Date) -> TrackingDay
    func interval(of: TrackingDay) -> DateInterval                  // 23 or 25 hours on DST days
    func week(containing: TrackingDay) -> [TrackingDay]             // Monday first
    func periods(_: Granularity, covering: ClosedRange<TrackingDay>) -> [TrackingPeriod]
    static func day(of: TimeEntry) -> TrackingDay
    static func midnights(after: Date, before: Date, in: TimeZone) -> [Date]
}
```

Views use `TrackingCalendar(timeZone: .current)`, rebuilt on a time zone change. Durations are integer seconds throughout; rounding happens only in formatting.

## 9. Testable behaviors

1. Creating a client creates one area with `general` true, the client's name, and `sortOrder` 0; renaming the client renames that area.
2. Renaming, retiring, reordering, or deleting a general area fails with `generalArea`; changing its color succeeds.
3. Duplicate folded names fail with `duplicateName`: clients, areas within a client (including a non-general area named like the client), projects within a client, and moving a project into a client with that name; the same project name in another client succeeds.
4. Deleting a client fails with `referenced` while it has another area or a live project; otherwise it and its general area are tombstoned together.
5. A `start` while an entry runs stops it at the new start.
6. The errors `projectArchived`, `areaRetired`, and `activeProjects` occur as in 1.2 and 1.3; restoring a project un-retires its area.
7. Archiving leaves entries untouched and hides the project from `projectTree(includeArchived: false)` and `distinctTasks`; a client whose projects are all archived is retired and omitted by `clients(includeRetired: false)`.
8. The query `clients(includeRetired: true)` returns "alpha", "Beta", "Émile", "zeta" in that order.
9. With a `ManualClock` at 10:00, a `create` ending 10:01, `start(at:)` 10:00:01, and a `move` past 10:00 fail with `inFuture`; `start(at:)` 10:00 succeeds; `end < start` fails with `endBeforeStart`.
10. The color `#2e8bc0` is stored as `#2E8BC0`; `2E8BC0`, `#2E8BC`, and `blue` fail with `invalidColor`.
11. Default color: hue 210 with no areas, 240 with hues 0 and 120, 45 with hues 0, 90, 180, 270; areas below saturation 0.1 are ignored; saturation 0.65 and brightness 0.80 within rounding.
12. A deleted entry disappears from reads unless `includeDeleted`; `restore` within 180 days brings it back; after 180 days it is hard-deleted and `restore` fails with `retentionExpired`.
13. An overlapping `create` is accepted, `overlaps(for:excluding:)` returns the intersecting entries minus the excluded id, and `overlappingEntries(in:)` lists the pair.
14. The query `consistencyIssues()` reports a project in a tombstoned area, an unknown project id, duplicate names, and a running entry 6 minutes in the future, and nothing on the `small` fixture.
15. Every write appends one outbox row per changed record and posts one Darwin notification; a failed write does neither.
16. The query `recentProjects(limit: 5)` returns the five projects with the latest entry starts, most recent first, each once.
17. In `Europe/Berlin`, a `create` from 22:00 on 2026-03-02 to 01:30 stores the given id until 00:00 and a piece from 00:00 with id UUIDv5(namespace: id, name: `split:2026-03-03`), copied fields, `splitRootID == id`, `createdAt` 00:00, each with its own `day`.
18. A running entry started at 23:00 is split when the clock passes 00:00; `runningEntry()` returns the continuation and its `chainStart(of:)` is 23:00.
19. A running entry from Monday 2026-10-26 22:00, after a simulated wake on Wednesday 10:00, yields three pieces with ids from `split:2026-10-27` and `split:2026-10-28`; a device that split the same entry night by night holds identical pieces after sync.
20. Editing a stopped entry's end from 23:30 to 00:45 creates the continuation; editing or deleting one piece afterwards leaves the others; an entry ending exactly at 00:00 is not split; a tombstoned derived id stays deleted.
21. In `America/Sao_Paulo`, an entry from 22:00 on 2018-11-03 to 02:00 on 2018-11-04 splits at 01:00, that day's start.
22. An entry recorded in `America/New_York` from 20:00 to 23:00 is not split on a device now in `Europe/Berlin`, and its `day` is the New York date.
23. Two or three running entries reduce so the latest start runs and each earlier one ends at the next start; with equal starts the greater root id runs and the other is tombstoned; the cross-midnight example of 3.3 yields the stated result on both devices; a second pass changes nothing.
24. The event `.adjusted` with `stoppedByLaterStart` and the causing device is emitted when this device's own running entry is stopped after a remote batch, not for entries created elsewhere, and never for `splitAtMidnight`.
25. With `InMemoryTransport`, a start on A appears on B after one cycle with identical `id`, `start`, `end`, and `day`.
26. A starts at 09:00 and B at 09:10 while partitioned; afterwards both hold A's entry ending at 09:10 and B's running.
27. A renames a project while B archives it, partitioned; both converge on the later change. A deletes an entry and B later edits it offline; the entry is live on both.
28. An entry whose project arrives in a later batch is kept and reported until the project arrives.
29. A `serverRecordChanged` rejection resolves without a second rejection; `zoneNotFound` re-sends every live record and tombstone; tombstones older than 180 days disappear on both devices.
30. Settings changed on both devices converge per key to the later value; `activity.contextColors` converges to the union, the smaller index winning.
31. Outbox rows from a second store instance without an engine (the CLI) are sent by the instance holding the engine.
32. A `start` writes the `live_state` snapshot of 4.1 (with `clientName` and `chainStart`) and queues `LiveState` in the entry's transaction and batch; a `stop` writes `running` absent; after a midnight split the snapshot names the continuation with unchanged `chainStart`.
33. A device applying that batch queues no `LiveState`; renaming the running project there queues a snapshot with the new name; a conflict merges as in 4.1.
34. The `LiveStatePublisher`, fed `current.json` files, writes at once on a presence, `agentRunning`, or `health` change, writes primary-item changes at most once per 30 seconds with the latest values, sets `agentRunning` false within 30 seconds after `last_tick` turns 2 minutes old, and writes nothing when only `last_tick` advances.
35. With a fake transport, a confirmed `LiveState` save on the Mac sends one request per iPhone or iPad with a token and none to others; a fetched `LiveState` with a changed running part sends, one changing only another Mac's activity does not; activity-only pushes to a token are at most one per 60 seconds; without the APNs key the status is `noKey` and nothing is sent.
36. Export lists every live record with the fields of 5.1 in the stated order; two exports of unchanged data differ only in `generatedAt`; `includeDeleted` adds tombstones.
37. Export, import into an empty store with `includeSettings`, and export again gives the same document except `generatedAt` and `storeID`.
38. Re-importing a document reports only `unchanged` and `skippedDeleted` and writes nothing; a changed task updates that entry only; a locally tombstoned record stays deleted; a document record carrying `deletedAt` leaves the local live record unchanged.
39. An entry ending before its start, a color `teal`, two running entries, an unknown project, or a future entry fails with `invalidDocument` naming the JSON path, and the store is unchanged.
40. A client without a general area gets one with id UUIDv5(namespace: client id, name: `general-area`), once.
41. An imported entry from 22:00 to 02:00 becomes two pieces; an imported running entry starting before the local one stops at the local start; missing `timeZone` and `deviceID` default as in 5.2; `dryRun` reports the same and changes nothing.
42. A month file with a header, three blocks, a time zone change header, and a malformed line yields three blocks with correct instants and one counted parse error.
43. The query `blocks(in:)` across a month boundary reads both files and returns blocks by start, filtered by device when asked to each block's part on it, without excluded contexts.
44. Aggregating by hour of day a block from 09:50 to 10:20 gives 600 s to hour 9 and 1200 s to hour 10.
45. The call `currentState()` is `nil` without `current.json`; a rewrite produces a change event and today's `blocks(in:)` includes one block with `isOpen`; `detail(for:)` is `nil` without the detail log.
46. In `Europe/Berlin`, the March and October transition days are 23 and 25 hours long; 23:59:59 and 00:00:00 fall on consecutive days; weeks start on Monday and ISO week 1 of 2027 begins on 2027-01-04.
47. A daily report over split entries gives each day its own pieces, day buckets sum to the total, and each `DayGroup.totalSeconds` equals the report's value; the running entry counts to the query time and sets `includesRunning`.
48. A report by area puts a moved project's entries under its new area.
49. On the Mac, with a started sync engine and a `ManualClock`, a tick 29 seconds after the start fetches nothing and one at 30 seconds fetches once; activating the app fetches at once and restarts the 30-second period; a second request while a fetch is in flight starts none.
50. Replacing the sleep periods from March 10 with the same night and a new nap keeps the night's record and creates one; a night starting March 9 is ignored; a shifted night tombstones the old record; after a sync the other device holds the same live periods and an empty outbox.
51. Asleep samples 23:00 to 01:00, 00:30 to 02:00, and 02:20 to 04:00 make one period 23:00 to 04:00, one at 06:00 another; an in-bed night without asleep samples is a period; two overlapping workouts are one; the first import starts 60 days before now, a later one 3 days before the previous; importing the same samples again changes nothing.

### 9.1 Fixtures

The generators `SyntheticDataset.small`, `.medium`, and `.large(seed:)` produce deterministic data: 3 clients, 6 areas, 15 projects, one month, about 250 entries; 8, 25, 90, three years, about 20,000; 10, 40, 120, ten years, 300,000. Workdays have 6 to 14 entries of 3 minutes to 3 hours (log-normal), with 10 percent evening work, 2 percent past midnight (stored split), configurable overlaps (default 0), 3 percent tombstones, 20 to 60 task phrases per project, 15 percent archived projects, default-rule colors, and an optional running entry. The call `Dataset.write(to:)` fills a store, `exportDocument()` produces the 5.1 document (used by the CLI tests), and `activityLog(to:)` writes block-log files that overlap the entries 70 percent of the time, with one time zone change.

## 10. Decisions

- Own SQLite schema with `CKSyncEngine`, not SwiftData: the running-entry and midnight rules need a custom merge, reports need SQL, scripts need a stable schema.
- Record-level last writer wins; a later edit may resurrect a deleted record.
- The one-running-entry rule and the midnight split run as a deterministic pass after every write and remote batch, so devices converge without coordination.
- Entries are split at midnight in storage with ids derived from the chain root and date, so daily totals are plain sums and every device produces the same pieces.
- No foreign keys: records sync in any order; integrity is reported, never repaired.
- A `LiveState` record plus Mac-sent WidgetKit pushes instead of a server: CloudKit silent pushes are throttled and the Mac is nearly always online.
- Import is the inverse of export, so converters for other products stay outside the app.

## 11. Interfaces

Provided:

- Entity types, `AreaColor`, typed ids, `StoreError` (1, 7.1).
- `TimeStoreWriting`, `TimeStoreReading` with `chainStart(of:)`, `StructureReading`, `Reporting`, `ReportCSVWriter`, `StoreObserving` (7).
- `SyncStatus`, `EntryAdjustment` (3).
- `LiveState`, `LiveStatePublisher`, `WidgetPushSender`, `WidgetPushStatus`, `LiveStateReader` (4).
- JSON export and `importDocument` (5), used by the CLI.
- `ActivityReading`, `DeviceEventSink`, `DeviceEventSource`, and the artifact table (6).
- `TrackingCalendar`, `TrackingDay` (8); setting keys and scopes (1.6).
- The store path, schema, and read-only script contract (2.1).

Assumed:

- Architecture: `<APP_ID>`, App Groups, `iCloud.<APP_ID>` in the development environment, `<APP_ID>.changed`, GRDB.swift, the CloudKit entitlement on the widget extension, the APNs credentials and request (§2.4).
- Tracker: log formats, blocks closed at midnight, `DeviceEvent` access only through `DeviceEventSource`.
- iOS: calls `setWidgetPushToken`, uses `LiveStateReader` in timeline providers, appends through `DeviceEventSink` and calls `flush()`, shows `.adjusted` as a banner.
- Timer and Calendar: refuse future entries and decide on overlaps before writing; the settings window shows `WidgetPushStatus`.
- Projects and Reports: tint and lightness-step parameters for `AreaColor`; Projects offers "Merge into" and reassignment for duplicates and orphans.
- Automation: the CSV columns of `ReportCSVWriter`.
- Calendar: time blocks live in the EventKit calendar `calendar.timeBlockCalendarID`.
- Activity: the hue sequence that `activity.contextColors` indexes.
