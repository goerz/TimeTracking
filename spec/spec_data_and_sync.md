# Spec: Shared Library, Data Model, and Sync

The shared library (`TimeTrackingCore`) is linked by every executable. It holds the entities and their invariants, the store, iCloud sync, the live-update path to the iPhone and iPad widgets, JSON export and import, the reader for the tracker's logs, and the queries behind every view and script. User interfaces hold views and view state only.

In this spec, lowercase "midnight" is the real midnight of the local clock, and capitalized "Midnight" is the setting of section 8.

## 1. Entities

Identifiers are lowercase UUIDs: version 4 for new records, version 5 for derived ones (split pieces, 1.5; generated general areas, 5.2). Times are instants with second precision. Name uniqueness compares case-, diacritic-, and width-insensitively after trimming ("folded"). Records carry the bookkeeping of 1.7.

### 1.1 Client

A client has an `id` and a `name`, non-empty after trimming and unique among live clients. Clients are listed alphabetically by folded name. A client has exactly one general area (1.2), created in the same transaction. A client is retired when none of its areas holds an active (live, unarchived) project; this is derived at query time, never stored. A client can be deleted only when it has no other area and no live project; deletion tombstones it and its general area together.

### 1.2 Area

| Field | Meaning |
|---|---|
| clientID | Never changes. |
| name | Non-empty; unique within the client; only the general area may carry the client's name. |
| general | True for the client's general area; fixed at creation. |
| color | `#RRGGBB`, sRGB. Accepted in either case and stored uppercase; anything else fails with `invalidColor`. |
| sortOrder | Position within the client: 0 for the general area, at least 1 for the others. |
| retired | Hidden from pickers and project creation; history keeps reporting. |

Renaming a client renames its general area in the same transaction. The general area cannot be renamed separately, reordered, retired, or deleted (`generalArea`); its color can change. Retiring an area with an active project fails (`activeProjects`). Creating a project in a retired area or moving one there fails (`areaRetired`); restoring a project of a retired area un-retires it. An area can be deleted only when no live project references it. A project's color is its area's; projects and entries store none.

Default color of a new area (including a new client's general area): take the HSB hues (whole degrees) of all live areas with saturation at least 0.1. With none, use hue 210. Otherwise take the midpoint, rounded down, of the largest circular gap between sorted hues (on equal gaps, the one starting at the smallest hue). The color is that hue at saturation 0.65 and brightness 0.80, rounded per sRGB channel.

Text on an area color is black or white, whichever has the higher WCAG contrast; [spec_projects.md](spec_projects.md) §4.4 defines tints and lightness steps.

### 1.3 Project

| Field | Meaning |
|---|---|
| areaID | May change, also to another client's area. |
| name | Non-empty; unique among the client's live projects. |
| archived | Hidden from pickers and autocompletion; entries kept; restorable. |
| archivedAt | Set when archived, cleared when restored. |

Moving a project into a client that has a live project of that name fails with `duplicateName`. Starting or continuing an entry on an archived project fails with `projectArchived`; a running entry whose project is archived elsewhere keeps running. A project with live entries cannot be deleted (`referenced`); merging moves all its entries to another project and tombstones it.

### 1.4 Time entry

| Field | Meaning |
|---|---|
| projectID | Nil means no project. |
| task | Free-text description, trimmed, may be empty. |
| start, end | Instants; `end` is nil while running, otherwise `end >= start`. |
| timeZone | IANA zone of the creating device; decides the entry's stored day and its midnights. |
| deviceID | Creating device (1.8). |
| splitRootID | For a split piece, the id of the chain's first piece. |

Duration is `end - start` (`now - start` while running), never stored or rounded. Invariants:

1. At most one live entry runs across all devices (3.3).
2. No live entry crosses a midnight of its `timeZone` (1.5); ending exactly at midnight is fine.
3. No library write sets `start` or `end` after the writing device's current time (`inFuture`). Synced records are not checked; a running entry starting more than 5 minutes in the future is a consistency issue.
4. Overlaps are tolerated; callers check for them before writing.
5. A reference to a project not yet received is kept, shown as "unknown project", and reported as a consistency issue.

### 1.5 The midnight split and the chain

Entries are split at midnight in storage, so daily sums are plain sums, with derived ids, so every device produces the same pieces. A midnight is `Calendar.startOfDay` in the entry's `timeZone`, which handles zones whose DST change falls at midnight.

An entry whose interval (up to now while running) contains midnights M1 < … < Mk after `start` becomes k + 1 pieces. The original keeps its id and ends at M1; the piece starting at Mi ends at the next midnight, at the original end, or keeps running. Each piece copies `projectID`, `task`, `timeZone`, and `deviceID`, has `createdAt = Mi`, `splitRootID = R` (the original's `splitRootID ?? id`), and id UUIDv5 (RFC 9562) with namespace R and name `split:YYYY-MM-DD`, the local date of Mi.

A running entry is split when a writing process sees a midnight pass: at each midnight of the entry's zone, on opening the store, on wake, on a clock or significant time change, and on every write. Creating, editing, moving, or importing across midnight splits in the same transaction; the write returns all pieces, the given id first. Pieces are ordinary entries afterwards and are never joined. A derived id that exists as a tombstone stays deleted and that part of the interval is dropped. Until a writer splits a running entry, read-only openers see it as one entry on its stored `day`.

An entry's chain is the live entries with the same root (`splitRootID ?? id`); its chain start is their earliest `start`. Running-entry displays (Timer label, menu bar, widgets) count elapsed time from the chain start.

### 1.6 Settings

Synced settings are records; device settings live in the App Group's `UserDefaults` suite. The feature specs describe what each setting does ([spec_timer.md](spec_timer.md) §5.2, [spec_calendar.md](spec_calendar.md) §6, [spec_ios.md](spec_ios.md)).

| Key | Scope | Default |
|---|---|---|
| `day.midnightHour` | synced | 0, range 0 to 23 (section 8) |
| `pomodoro.focusMinutes`, `pomodoro.breakMinutes` | synced | 25, 5 |
| `pinnedProjectIDs` | synced | empty |
| `activity.contextColors` | synced | empty (context to hue index) |
| `calendar.snapMinutes` | synced | 5 |
| `calendar.shownCalendars` | synced | empty |
| `calendar.timeBlockCalendarID`, `calendar.timeBlockCalendarTitle` | synced | nil (no title means "Time Blocks") |
| `calendar.showSleep`, `calendar.showWorkouts` | synced | false |
| `calendar.sleepAreaID`, `calendar.workoutAreaID` | synced | nil |
| `calendar.healthImport` | synced | nil (written by the iPhone's import, 1.9) |
| `pomodoro.sounds` | device | true |
| `idle.thresholdMinutes` | device | 10 |
| `deviceID` | device | a UUID created on first use |

Synced settings merge per key by last writer, except `activity.contextColors`, which merges as the union, the smaller index winning for a context assigned differently. A new context takes the hue index used by the fewest contexts, lowest on ties.

### 1.7 Bookkeeping

Records have `createdAt` (a split piece's: its midnight; settings have none), `modifiedAt` (the last local change in milliseconds by the writing device's clock, which drives conflict resolution, 3.2), and `deletedAt`, set by every deletion (devices have none). Tombstones are invisible unless `includeDeleted` is requested and are hard-deleted locally and in CloudKit after 180 days. Deleting anything a live record references fails with `referenced`.

### 1.8 Device

A device record has the `deviceID` setting as id, a user-visible `name`, a `platform` (`mac`, `iphone`, or `ipad`), `lastSeenAt` (updated at most hourly while the app runs), and on iPhone and iPad `widgetPushToken`, the widget extension's WidgetKit push token in hex, nil without installed widgets. Devices are never deleted automatically.

### 1.9 Health period

| Field | Meaning |
|---|---|
| kind | `sleep` or `workout`. |
| start, end | Whole seconds. |
| activity | A workout's `HKWorkoutActivityType` case name (`running`), or `other-` and the raw value for a type the iPhone's table doesn't name. Nil for sleep and for workouts imported before schema version 3. |
| distance | A workout's distance in whole meters, summed over what it records (a swim-bike-run has three); otherwise nil. |

Sleep and workouts from Apple Health, for the Calendar ([spec_calendar.md](spec_calendar.md) §3.1). Only the iPhone imports and writes them ([spec_ios.md](spec_ios.md) §7 item 6); they sync to the Mac and iPad and are not part of the JSON export.

A sleep period is the asleep samples of any stage merged where they overlap or lie at most 30 minutes apart, plus each in-bed period holding no asleep sample (a night recorded by the sleep schedule alone). A workout period runs from a workout's start to its end; overlapping workouts (one workout recorded by two apps) merge, while workouts that only touch stay apart. A merged period takes the activity and distance of its longest workout, since a sum would count the same exercise twice.

An import of one kind covers the 60 days before now the first time, afterwards from 3 days before the previous import (a watch syncs late), and reads samples from a day earlier still, so a period that began before the range is whole. The live periods of that kind starting in the range then become the imported ones: a period with the same start and end keeps its record (updated when its activity or distance differs), the others become tombstones, and new ones are created. The workout import's timestamp changed key with schema version 3, so the first import after the upgrade covers 60 days again and fills in activity and distance.

After an import in which at least one kind succeeded, the iPhone writes `calendar.healthImport` (device name, time, kinds read) for the Calendar settings' status line, unless the stored status has the same device and kinds and is less than an hour old, so frequent wakes don't each sync a record.

## 2. Persistence

### 2.1 Store and schema

The store is the product's own SQLite schema rather than SwiftData, because the running-entry and midnight rules need a custom merge, reports need SQL, and scripts need a stable format. It is one database in WAL mode at `<App Group container>/Library/Application Support/TimeTracking/store.sqlite` (spec_architecture.md §1.5; Debug builds have their own). The tracker agent does not open it. Timestamps are Unix seconds except `modified_at` (milliseconds); booleans are 0/1.

Entity tables (`client`, `area`, `project`, `time_entry`, `setting`, `device`, `health_period`) hold the fields of section 1 in snake case, with `setting` as `key` and JSON `value`. The `time_entry` table adds the computed `day` (`YYYY-MM-DD`, the local date of `start` in `time_zone`) and `task_key` (the folded task). The tables `meta` (`schema_version`, currently 3, and `store_id`), `live_state`, `outbox`, `sync_state`, and `purged_record` (hard-deleted ids, so `restore` can report `retentionExpired`) are internal. Scripts read entries through this view, whose `day` is the stored day whatever Midnight says:

```sql
CREATE VIEW entries AS
  SELECT e.id, e.start, e."end", e."end" - e.start AS seconds, e.day, e.task,
         p.id AS project_id, p.name AS project, a.id AS area_id, a.name AS area, a.color,
         c.id AS client_id, c.name AS client, e.device_id, e.time_zone
  FROM time_entry e LEFT JOIN project p ON p.id = e.project_id
       LEFT JOIN area a ON a.id = p.area_id LEFT JOIN client c ON c.id = a.client_id
  WHERE e.deleted_at IS NULL;
```

No foreign keys are declared, since records sync in any order; integrity is reported, never repaired. Migrations run forward on open and only add columns and tables; a newer schema than the library knows is refused.

Scripts open the file read-only (`?mode=ro`) and may rely on the `entries` view and the `client`, `area`, `project`, and `setting` tables, whose columns are stable within a major schema version (columns may be added). Everything else is private (scripts list health periods with the tool's `health`); scripts write through the command-line tool.

### 2.2 Processes and change notification

Writers are the app and, on the Mac, the command-line tool; iOS widget and control buttons write through intents that run in the app process. A 5-second busy timeout serializes them; a write still locked out fails with `busy`. Each write transaction runs the invariant pass (3.3), appends one `outbox` row per changed record, and after commit posts the Darwin notification `<APP_ID>.changed`, the only cross-process change signal.

Every listener receives every post, its own included, and posts close together arrive as one. A store therefore re-reads when `PRAGMA data_version` of its writer connection shows that another connection committed, so another process's post that arrived with its own is not lost. The command-line tool posts but does not listen.

Only the app runs the sync engine and drains the outbox: on the Mac within a second, on iOS at the app's next run. After applying remote changes, the iOS app reloads all widget timelines.

## 3. Synchronization

### 3.1 CloudKit layout and engine

The private database of `iCloud.<APP_ID>` (development environment) holds the zone `TimeTracking` with the record types `Client`, `Area`, `Project`, `TimeEntry`, `Setting`, `Device`, `HealthPeriod`, and `LiveState`, and the zone `ActivityEvents` with `DeviceEvent` (section 6). Record names are the UUIDs (for `Setting` the key, for `LiveState` the fixed name `LiveState`); fields use the camelCase names of section 1; references are `String` UUIDs, so nothing cascades. Record types and fields are only ever added.

A `CKSyncEngine` runs in the app process with automatic sync and a database subscription for silent pushes:

1. Every store change hands the outbox to the engine; a change to the running entry or `LiveState` is sent at once.
2. A batch containing a `LiveState` save is atomic by zone and includes the entry records that produced it.
3. A `serverRecordChanged` conflict merges (3.2, 4.1) and re-queues; `unknownItem` re-saves without system fields; `zoneNotFound` recreates the zone and re-queues every live record and tombstone.
4. Fetched changes are applied in one transaction followed by the invariant pass. A remote hard deletion of a live local record acts as a tombstone at `now`.
5. A switch to another iCloud account resets the store to empty after confirmation; declining stops sync. With no account the store works locally.

CloudKit throttles silent pushes, so the apps also fetch on their own. The Mac app fetches whenever it becomes active and 30 seconds after its last fetch, one fetch at a time; iOS fetches at every foreground, before acting on a widget or control button, and in its refresh task (iOS spec §6.1, §7).

A start or stop on one online device appears in the app on another within 5 seconds in the common case and 30 seconds at worst. Writes never wait for the network. The sync status is `idle`, `sending(count)`, `fetching`, `waitingForNetwork`, `noAccount`, or `error(message)`.

### 3.2 Conflict resolution

The copy with the later `modifiedAt` wins entirely; on a tie the greater `deviceID`, then the greater field text, so every device picks the same copy. Deletion is an ordinary modification, so a later edit resurrects a deleted record. The only field-level merges are `activity.contextColors` (1.6) and `LiveState` (4.1). The same project name created on two devices yields two projects, reported for "Merge into". A project added to an area whose client was deleted elsewhere is reported as orphaned for reassignment, never deleted. The Mac app's daily maintenance hard-deletes tombstones older than 180 days, and the deletion syncs to the other devices.

### 3.3 The invariant pass

The one-running-entry rule and the midnight split run as a deterministic pass, so devices converge without coordination. After every local write and every applied remote batch, in the same transaction, as a pure function of the store and the current time:

1. Split every running entry and every entry the transaction changed that crosses a midnight of its zone (1.5).
2. If several entries run, order them by chain start, then root id. The last keeps running. For each other one, with T the next one's chain start: entries of its chain with `start >= T` are tombstoned, and the one with `start < T` that runs or ends after T gets `end = T`.

Changed rows get `modifiedAt = now` and are queued; the pass never reopens an entry. Example: A starts X at 23:00 offline and B starts Y at 23:30, and both split at midnight while apart; every device ends with X from 23:00 to 23:30, Y from 23:30 to midnight, Y's continuation running, and X's continuation tombstoned.

The pass repairs nothing else. The query `consistencyIssues()` reports a running entry starting more than 5 minutes ahead of this device's clock, dangling references, and duplicate names.

Every change the pass or conflict resolution makes to an entry is an adjustment, kept in a ring of 100 and the `os` log, with reason `splitAtMidnight`, `stoppedByLaterStart`, `removedByLaterStart`, `replacedByRemoteEdit`, `deletedRemotely`, or `restoredRemotely`. Adjustments other than `splitAtMidnight` to entries created on this device are emitted as `.adjusted`, which the iOS app shows as a banner ([spec_ios.md](spec_ios.md) §7).

## 4. Live updates

The running entry and each Mac's current activity reach iPhone and iPad widgets within seconds through the `LiveState` record, widget push tokens on `Device` records, and WidgetKit pushes sent by the Mac app. There is no server: CloudKit silent pushes are throttled, and the Mac is nearly always online.

### 4.1 The `LiveState` record

One record named `LiveState` in zone `TimeTracking`, mirrored in the `live_state` row.

| Field | Type | Meaning |
|---|---|---|
| running | String (JSON) or absent | `{"entryID", "projectID", "task", "projectName", "clientName", "areaColor", "chainStart"}`; project fields null for no project; `chainStart` RFC 3339 UTC. Absent when nothing runs. |
| changedAt | Date | Last change of the running part, milliseconds. |
| activity | String (JSON) | Map from a Mac's device id to `{"device", "primary", "groupKey", "presence", "since", "agentRunning", "lastTick", "health", "updatedAt"}`. |

The activity fields come from that Mac's `current.json` (tracker spec §4.4): `primary` is `[context, subject, detail]` or null, `groupKey` the open block's `g` or null, and `health` the ids of sources whose status is not `active`.

On a conflict the running part with the later `changedAt` wins, and per Mac the activity entry with the later `updatedAt` wins; ties pick the greater JSON text. Entries present on one side only are kept.

### 4.2 Writers

Running part, any writing process: after each write transaction the library computes the snapshot and, if it differs from the local row, writes it with `changedAt = now` and queues `LiveState` in the same transaction. A row naming the same entry and project is kept while that project has not arrived, so a receiver never replaces a complete snapshot with a partial one. Applying a remote `LiveState` updates the local row first, so the receiver writes nothing.

Activity part, Mac app only: the app watches the local `current.json` and writes this Mac's entry. Changes of `presence`, `agentRunning`, or `health` are written at once; changes of `primary` or `groupKey` at most once per 30 seconds, a change inside the window being written at its end with the then current values. A `lastTick` change alone writes nothing; `agentRunning` is re-evaluated every 30 seconds. Without `current.json` the entry stays, with `agentRunning` false.

### 4.3 Widget pushes

The iOS app stores its widget push token on its `Device` record (iOS spec §4, item 1). Only the Mac app sends pushes (spec_architecture.md §2.4), to every `iphone` or `ipad` device with a token, when the engine confirms the Mac's own `LiveState` save and when it applies a fetched `LiveState` whose running part changed. Another Mac's activity change sends nothing, since that Mac sends its own.

Running-part pushes go out at once; activity-only pushes at most once per 60 seconds per token, a later one being sent at the window's end. With two Macs, duplicates only cause an extra reload. The push status is `noKey` (no pushes), `idle(lastSentAt)`, or `failing(message)`.

Widget timeline providers fetch the record from CloudKit without the sync engine (iOS spec §4, item 2). With the Mac awake and online, a stop on any device reaches a Home Screen widget in about 5 seconds; otherwise widgets follow CloudKit pushes, app runs, and scheduled reloads.

## 5. JSON export and import

### 5.1 Export

The command `timetracking export` writes the whole store as one document, the backup and interchange format:

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

The command `timetracking import` reads the same format and upserts by id. Import is the inverse of export, so converters for other products stay outside the app (spec_automation.md).

Required: `format` 1; clients `id`, `name`; areas `id`, `clientID`, `name`, `color`; projects `id`, `areaID`, `name`; entries `id`, `start`, `end`. Missing optional fields default to `sortOrder` 0, false flags, null `archivedAt`, `projectID`, and `splitRootID`, empty `task`, `createdAt` now, `timeZone` `options.defaultTimeZone` (else the device's zone), and `deviceID` the importing device. The import ignores `generatedAt`, `storeID`, and `devices`, and applies `settings` only with `options.includeSettings`.

In one transaction:

1. Validate everything: format, required fields, UUIDs, colors, time zones, `end >= start`, nothing in the future, at most one running entry, resolvable references, and the name rules on the resulting store. The first failure throws `invalidDocument(path:reason:)` with a JSON path such as `entries[1041].end`, and nothing is written.
2. Give a client without a general area one with id UUIDv5(namespace: client id, name: `general-area`), the client's name, and the default color.
3. Upsert by id: insert new rows, replace changed live rows, skip equal ones, and skip local tombstones (`skippedDeleted`). Document records that carry `deletedAt` are ignored, so an import never deletes. Written rows get `modifiedAt = now`.
4. Run the invariant pass.

The report counts `created`, `updated`, `unchanged`, and `skippedDeleted` per entity, plus `splitPieces` and adjustments. With `options.dryRun` the transaction is rolled back.

## 6. Activity logs

The tracker spec defines the formats and folders ([spec_activity_tracking.md](spec_activity_tracking.md) §4.1).

| Artifact | Location | Writer | Readers |
|---|---|---|---|
| `Activity/blocks/<mac>/YYYY-MM.jsonl` | iCloud Drive container, outside `Documents/`; local fallback in the App Group | Each Mac's agent, only its own subfolder | Mac app, iPhone, iPad, scripts |
| `Activity/settings.toml` | Same folder | The Mac app's Tracker pane | Agent, iOS app (exclusions) |
| `Activity/current.json` | Mac, local | Agent, every tick | Mac app |
| `Activity/detail/YYYY-MM-DD.jsonl` | Mac, local | Agent | The recording Mac; scripts |
| `DeviceEvent` records | CloudKit zone `ActivityEvents` | iOS app | Agent |
| `Activity/events.jsonl` | iOS, App Group | iOS extensions and app | iOS app (flushes to CloudKit, truncates) |

The iPhone and iPad learn the Mac's current activity only from `LiveState`. A `DeviceEvent` carries `deviceID`, `time`, `source` (`ladder`, `focus`, `intent`, `webext`, `app`), `label`, `kind`, and an optional JSON `payload`. The record name `<deviceID>-<time in ms>-<sequence>` makes an interrupted flush resume without duplicates. The agent merges events into the user's timeline (tracker spec §2.4) and deletes records older than 90 days.

The reader skips headers, counts malformed lines for health, converts local times with the latest header's `tz`, and re-reads a month file when it changes. Blocks with the same id count once. Exclusions in the current `settings.toml` apply to every read, and a device filter keeps each block's part on those devices. Block detail exists only on the recording Mac. A block is mostly reconstructed when reconstructed time exceeds half its active time. On the iPad the app asks iCloud Drive for the current month's file and rechecks every 60 seconds. The tracker closes blocks at midnight, so the reader never splits them.

## 7. Query layer

Views and scripts read and write through `async` APIs on the store's serial executor.

### 7.1 Writing

Every write validates, writes, runs the pass, queues, and notifies; several writes can share one transaction and one pass. Starting stops the running entry at the new start. Creating, updating, and moving an entry return its split pieces, the given id first. A user split gives the second part a random id. The `StoreError` cases are `emptyName`, `duplicateName`, `projectArchived`, `areaRetired`, `generalArea`, `activeProjects`, `invalidColor`, `endBeforeStart`, `inFuture`, `referenced`, `unknownID`, `retentionExpired`, `invalidDocument`, `newerSchema`, `readOnly`, `busy`, and `database`.

### 7.2 Reading

The query `entries(in:)` returns entries intersecting an interval, and `entries(on:)` those with that stored `day`. The Timer list reads `days(ending:count:)`: shown days (section 8), newest first, empty days included, each with its entries or pieces, a total with the running entry counted to the query time, and whether it includes the running entry.

Task autocompletion matches the folded prefix against `task_key`, skips archived projects, returns each task once by most recent use, and without a project searches entries without one. The project picker's task matching looks back 90 days.

### 7.3 Reports

A report takes a range of shown days, up to four grouping levels (client, area, project, task, day), a granularity (day, week, month, year, total), and a filter.

It counts each entry in the shown days it lies on (with Midnight at 00:00 that is its stored `day`, section 8), the running one up to the query time, so the Timer list and Reports agree. Client and area grouping use the project's current area. A health kind that is shown and mapped to a live area adds one row per day it touches, its part of that day, under a fixed project id named "Sleep" or "Workouts" in that area, with an empty task ([spec_reports.md](spec_reports.md) §1.1). The tool's `report` includes health rows only with `--health`. A query's optional instant bounds keep only the entries starting inside them and cut health time at them (spec_automation.md §3.2). The query `entries(matching:)` selects stored entries by their stored `day`.

### 7.4 Observation

Same-process changes reach observers after commit. Other processes' changes arrive through the Darwin notification as an unspecific re-read of entries, the running entry, structure, health, and live state, plus the setting keys whose rows changed.

### 7.5 Performance

Targets on the `large` fixture (9.1) in an optimized build on a current Mac, checked by the library's performance tests in `make test`:

| Operation | Target |
|---|---|
| `runningEntry()` | under 1 ms |
| Single-entry write | under 5 ms |
| `entries(on:)`, `days(ending:count: 7)`, `entries(in:)` for 7 days | under 10 ms |
| `distinctTasks` with a 2-character prefix | under 20 ms |
| `blocks(in:)` for 7 days, month files cached; opening the store | under 50 ms |
| `report` over one year, four levels, by day | under 100 ms |
| `report` over ten years, four levels, by month | under 300 ms |
| Export of the whole store | under 10 s |
| `importDocument` | at the rate of 300,000 entries in 60 s |

## 8. Days, weeks, and time zones

Stored days start at midnight. A stored entry's `day` is the date of its `start` in its own `timeZone`, and the entry lies wholly within it; after travel, entries keep their recorded day. The tracker's blocks close at midnight and carry their local date too.

The synced setting Midnight (`day.midnightHour`, whole hours, default 00:00) sets the hour of the local clock at which the days the app shows and reports start: the Timer list, Calendar, Reports, Activity, Projects totals, widgets, and the tool's day ranges and `report`. People set it to the middle of their night. It changes no stored data and nothing the tracker collects, so changing it is instant, reversible, and rewrites no record. With Midnight at 00:00, shown days are the stored days. Views read `TimeStore.displayCalendar(timeZone:)` and rebuild it on a time zone change or a change of the setting; storage code keeps the plain `TrackingCalendar(timeZone:)`.

A shown day that starts before noon is named after the date it starts on; one that starts at noon or later after the date it ends on, so with Midnight at 04:00 "Tuesday" runs Tuesday 04:00 to Wednesday 04:00, and with 22:00 Monday 22:00 to Tuesday 22:00. Each local date holds one day change. Days last 23 or 25 hours across DST changes. An hour a DST change skips is replaced by the first instant after it; of an hour it repeats, the first counts. Weeks are Monday to Sunday of shown days, with ISO 8601 numbers.

Shown, an entry crossing the day change in its own zone is two *pieces* (`TrackingCalendar.pieces(of:at:)`) with the entry's id: each has its part of the interval and its day, only the last one runs, and each counts as an entry of its day, so sums over days stay plain sums. Entries split at a midnight inside a shown day stay two entries there. Editing always acts on the stored entry. While an entry runs, the apps wake at the start of the next shown day so its part moves over; with nothing running, they check every minute and reload when the shown day has changed. The tool's `entries` lists stored entries by their start (`spec_automation.md` §3.2). Activity blocks and background stretches keep one shown day, that of their start, because their items cannot be divided; the Calendar draws them in every column they reach.

Durations are integer seconds throughout; rounding happens only in formatting.

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
52. A run 18:00 to 18:45 (running, 7012 m), a copy 18:01 to 18:40 (6990 m), and a walk 18:45 to 19:00 make two workout periods: 18:00 to 18:45 running with 7012 m, and the walk; importing them over the same periods stored without details keeps the records, fills in activity and distance, and the other device receives them; the workout import key is `health.importedThrough.workout.3`.
53. The query `backgroundStretches(in:)` returns the stretches overlapping the interval, with the items of the asked devices and without excluded contexts; `blocks(in:)` never returns them.
54. When another process writes and posts and this process writes and posts before its listener runs, this process's observers still receive `.entries([])`, and `.settings` with each key the other process changed.
55. An edit made while its record is being sent stays queued after the send is confirmed and goes out with the next send; a batch's outbox sequence and records are read in one transaction.
56. With Midnight at 04:00, 03:59:59 on March 14 lies on March 13 and 04:00 on March 14, whose day lasts 24 hours; with 22:00, 21:59 on March 14 lies on March 14 and 22:00 on March 15, which starts on March 14; with 0 a day is the local date.
57. In New York with Midnight at 02:00, March 10, 2024 starts at 03:00 and lasts 23 hours; with 01:00, November 3 starts at the first 01:00 and lasts 25 hours, and the second 01:00 lies on it.
58. Midnight changes no stored entry: entries across it stay one record, entries across a real midnight stay split with their stored days; shown, an entry from 03:00 to 05:00 is pieces ending and starting at 04:00 with one id and the days March 12 and 13, a running entry's last piece runs, and an entry in another zone cuts at that zone's Midnight.
59. Midnight is 00:00 by default, syncs as a setting, and reaches `displayCalendar` on the other device.
60. Polling at 03:59 and 04:00 with Midnight at 04:00 reports one change of shown day, then none, and a change of Midnight that moves the day reports one.

### 9.1 Fixtures

The deterministic generators `SyntheticDataset.small`, `.medium`, and `.large(seed:)` produce 3 clients, 6 areas, 15 projects, one month, about 250 entries; 8, 25, 90, three years, about 7,000; and 10, 40, 120, ten years, about 24,000. Their entries include evening work, entries past midnight (stored split), tombstones, and archived projects. A dataset can fill a store, produce the 5.1 document, and write block-log files with one time zone change.
