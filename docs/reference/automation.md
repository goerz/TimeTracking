# Scripting Surface

Every way a program other than the app's user interface reads or changes tracked time: the command-line tool `timetracking`, App Intents, and the `timetracking` URL scheme, plus the CSV formats, the description file, and `check`. Everything runs on the device against the local store; there is no web API or `x-callback-url`. App Intents stand in for an AppleScript dictionary because one definition serves Shortcuts, Siri, and Spotlight on both platforms. Time blocks are calendar events ([calendar.md](calendar.md)), so no command touches them.

## 1. Principles

1. Every surface parses input, calls the library, and formats output; none holds business logic.
2. Read commands, including `check` without `--fix` and `import --dry-run`, open the store read-only and leave no mark.
3. Every listing has a JSON form and, where tabular, a CSV form. Their shapes change only with a format version bump; human-readable tables may change.
4. Scripts refer to projects, areas, and clients by name; every JSON record also carries the UUID.
5. URLs start, stop, continue, and show. Intents never delete. The tool deletes one entry at a time, only with `--yes`.

## 2. Store access

The tool runs in its own process, works without the app running, and writes through the library as one more outbox writer, with no XPC service ([data_and_sync.md](data_and_sync.md) §2.2). It never touches CloudKit; the app sends its outbox rows and the `LiveState` change. It lives in the app bundle at `Contents/Helpers/timetracking`, linked into `PATH` by `make install`, so tool and app versions never differ. App Intents and URLs run in the Mac or iOS app, launched in the background if needed.

## 3. The command-line tool

### 3.1 Global options

Every subcommand has `--help`; there are no abbreviations, and `timetracking --generate-completion-script zsh|bash|fish` writes completions. The `ALIAS` setting in `local.mk` adds a second name.

These options may come before or after the subcommand: `--json` and `--csv` (mutually exclusive), `--store PATH` (`TIMETRACKING_STORE` does the same; the option wins), `--quiet` or `-q` (no output on success for write commands), and `--no-color` (also with `NO_COLOR` or when stdout is not a terminal). Without a subcommand, `--store-path` prints the resolved store path and `--version` the tool and schema versions. The variable `TIMETRACKING_NOW` (ISO 8601) fixes "now" in Debug builds only. Times are read and printed in the system time zone.

### 3.2 Dates and ranges

Date arguments (`--from`, `--to`, `--day`, `--week`, `--month`, `--at`, `--start`, `--end`) accept `2026-10-29`, `2026-10-29T09:15` (offset optional), `2026-W44`, `2026-10`, the words `today`, `yesterday`, `tomorrow`, `week`, `last-week`, `month`, `last-month`, `year`, and `-3d`, `-2w`, `-1m`. A date option takes the next argument even when it starts with a dash.

Days run from one start of day to the next in local time, by default 00:00 ([data_and_sync.md](data_and_sync.md) §8), so `today`, `--day`, and `status` follow the setting and `report` cuts entries at it, while `entries` lists stored entries by their start, never in parts. Weeks run Monday to Sunday.

The range `--from A --to B` is half-open (`--to` names the first day excluded), so ranges compose without an "end of day" ambiguity; `--from` alone runs through today, and `--to` needs `--from`. A `--from` or `--to` with a time of day is an instant bound: the entries whose start lies in the half-open interval count, and either bound may be a day while the other is an instant. In JSON, `from` and `to` echo an instant as ISO 8601 with offset and a day as its date. The options `--day`, `--week`, and `--month` always mean whole days and exclude `--from` and `--to`. Defaults: `entries` and `health` today, `report` the current week. A range over 366 days is a usage error unless `--all-time` is given, which without a range means all time (`report` needs a range). Ranges may include future days.

### 3.3 Names and identifiers

The options `--project`, `--area`, and `--client` take a name, matched after trimming, case- and diacritic-insensitively ([data_and_sync.md](data_and_sync.md) §1). A write that names an archived project through `start` or `entry` refuses with exit 4, `Project "X" is archived; unarchive it first.`; filters and `project archive`, `unarchive`, `rename`, and `move` also match archived projects. A name found in several clients exits 3 and lists the candidates; `--client` or the form `Client/Project` resolves it. The options `--project-id` (`start`, `entry create`, `entry edit`) and `--entry-id` (`continue`) take UUIDs. Output uses lowercase UUIDs and upper-case `#RRGGBB`; input colors accept either case.

A write command prints one line describing the change (`Started "Clarify noise model" on Noise paper at 09:15.`), or with `--json` the changed record; `--quiet` suppresses the line, never an error.

### 3.4 Subcommands

The subcommands are `status`, `start`, `stop`, `continue`, `entries`, `entry`, `report`, `health`, `projects`, `clients`, `areas`, `project`, `area`, `client`, `check`, `import`, and `export`.

### 3.5 Status, start, stop, continue

The `status` command prints the running entry or `No entry running.`, today's total (the shown day's, including the running entry's part of it), and the count of unsent local changes, and exits 0 either way:

```json
{
  "running": {"id": "7b1a…", "start": "2026-10-29T09:15:00+01:00", "end": null, "duration": 1812, "running": true, "task": "Clarify noise model",
              "project": {"id": "5e0c…", "name": "Noise paper"}, "area": {"id": "a1f3…", "name": "Research", "color": "#0A9396"}, "client": {"id": "c9d2…", "name": "University"}},
  "today": {"date": "2026-10-29", "duration": 14532},
  "pendingChanges": 0,
  "asOf": "2026-10-29T09:45:12+01:00"
}
```

The field `running` is `null` when nothing runs. This object (with `running` false and `end` set for a stopped entry; `project`, `area`, `client` null without a project) is the entry record of every listing. Listings nest project, area, and client for scripts; the export references them by id for exact round trips.

| Command | Effect | Refused with exit 4 |
|---|---|---|
| `start [TASK] [--project NAME] [--at TIME] [--force]` | Starts an entry; stops a running entry at the new start and says so. Never infers a project | `--at` in the future, more than 24 hours back, before the running entry's start, or overlapping a stopped entry (unless `--force`); an archived project |
| `stop [--at TIME]` | Stops the running entry | Nothing running (`No entry running.`); `--at` before the start or in the future |
| `continue [--entry-id ID \| --project NAME \| --task TEXT]` | New entry with the task and project of: the most recent entry other than the running one; the given entry; or the most recent match (`--task` matches a substring). Stops a running entry first | Continuing the running entry itself |

### 3.6 Entries

The command `entries [range]` lists entries whose start lies in the range, ascending unless `--order desc`. It filters with `--project`, `--client`, `--area`, `--no-project`, and `--task` (a case-insensitive substring), limits with `--limit N`, and with `--running` lists only the running entry regardless of range. The table has a subtotal at each day change. JSON is `{"from", "to", "entries": [entry records], "total"}`, where `total` includes the running entry's elapsed time. With `--csv` it writes the Entries CSV (8.2).

The command `entry show ID` prints one entry. The commands `entry create [TASK] --start TIME --end TIME` and `entry edit ID` (with `--start`, `--end`, `--project` or `--no-project`, `--task`) take `--force`. The command `entry delete ID --yes` deletes one entry; without `--yes` it prints the entry to stderr and exits 2.

Create and edit refuse with exit 4 an overlap (unless `--force`), an end in the future, and an end before the start. An entry can span dates ([data_and_sync.md](data_and_sync.md) §1.5). There is no bulk delete.

### 3.7 Report

The command `report [range]` takes the filters of `entries`. The option `--group-by` is an ordered list of one to four distinct keys of `client`, `area`, `project`, `task`, `day` (default `client,area,project`); `--granularity` is `total` (default), `day`, `week`, or `month`. The tool calls the report query Reports uses, so an entry crossing the start of day counts in each shown day it lies on. The table prints durations as `h:mm:ss`, or decimal hours with two decimals under `--hours`. The sleep and workouts that Reports count ([reports.md](reports.md) §1.1) count here only with `--health`, so a script's totals are tracked time unless it asks for more. With an instant bound (3.2), the entries starting inside the interval count whole, not cut at the bounds, while health time is cut at the bounds; the periods are those of the days the interval touches. JSON:

```json
{
  "from": "2026-10-19", "to": "2026-10-26", "granularity": "day", "groupBy": ["client", "area", "project"],
  "rows": [{"period": "2026-10-20", "client": "University", "area": "Research", "project": "Noise paper", "duration": 7380, "entries": 3}],
  "periods": [{"period": "2026-10-19", "duration": 0}, {"period": "2026-10-20", "duration": 7380}],
  "total": 7380
}
```

Rows with zero duration are omitted; `periods` lists every period including empty and future ones. A row has only the `groupBy` keys (null for entries without a project) plus `duration` and `entries`. The `period` is the day's date (`day`), `2026-W43` (`week`), `2026-10` (`month`), or `"total"`. With `--csv` the tool writes the Breakdown CSV (8.2), with a first column `period` unless the granularity is `total`.

### 3.8 Structure listings

The command `projects [--active|--archived|--all] [--client NAME] [--area NAME] [--sort name|client|area|last-entry]` lists projects (default active, sorted by client, area, name). JSON: `{"projects": [{"id", "name", "state", "area": {"id", "name", "color"}, "client": {"id", "name"}, "createdAt", "archivedAt", "lastEntryAt"}]}` with `state` `"active"` or `"archived"`.

The command `clients` lists clients alphabetically: `{"clients": [{"id", "name", "areaCount", "activeProjectCount"}]}`. The command `areas [--client NAME] [--retired]` prints `{"areas": [{"id", "name", "color", "retired", "general", "client": {"id", "name"}, "activeProjectCount"}]}`; `--retired` includes retired areas. With `--csv` the three print the structure tables of 8.2.

The command `health [range] [--kind workout|sleep]` lists the health periods ([data_and_sync.md](data_and_sync.md) §1.9) whose start lies in the range, ascending, whatever the Calendar settings show, then the last import. JSON: `{"from", "to", "lastImport": {"device", "at", "kinds"} | null, "periods": [{"id", "kind", "activity", "start", "end", "duration", "distance"}]}`, with `--csv` `id,kind,activity,start,end,seconds,distance`. Here `lastImport` is the synced `calendar.healthImport` (the iPhone's name, its last import that read at least one kind, rewritten at most hourly, and the kinds read), so a script tells "no workout yesterday" from "not imported since" by comparing `lastImport.at` with the end of the day. The fields `activity` and `distance` (whole meters) are null when unknown. Ids change when Health changes a period's start or end, so scripts don't keep them across imports.

### 3.9 Managing projects, areas, clients

The subcommands `project create|archive|unarchive|rename|move`, `area create|rename|set-color`, and `client create|rename` change the structure; there is no command to delete a project, area, or client. They take a name, plus `--area`, `--client`, and `--color #RRGGBB` as `--help` shows.

They refuse with exit 4 a name already taken (for `project create`, by an active or archived project of the client), archiving what is archived, unarchiving what is active, creating a project in a retired area, and renaming a general area. Archiving keeps the project on its entries. Moving goes to an area of any client; a target not found exits 3. A malformed color exits 2. A new area without `--color` gets the default of [data_and_sync.md](data_and_sync.md) §1.2. Creating a client creates its general area, and renaming it renames that area too.

### 3.10 Import and export

The command `export [-o PATH] [--include-deleted]` writes the JSON export ([data_and_sync.md](data_and_sync.md) §5.1) to a file or stdout. The command `export --format csv [range] [--what entries|projects|areas|clients|all] [-o PATH]` writes the Entries CSV (default all time) or a structure table (8.2); with `--what all`, `-o` is required and names a directory receiving `entries.csv`, `projects.csv`, `areas.csv`, and `clients.csv`. A range or `--what` without `--format csv` is a usage error.

The command `import FILE [--dry-run] [--include-settings]` validates the whole document, upserts by id in one transaction, and never deletes ([data_and_sync.md](data_and_sync.md) §5.2). A document that fails validation exits 7 with the JSON path and reason, and nothing is written. The option `--include-settings` also applies the synced settings. The tool prints one line per kind, `entries: 1520 created, 3 updated, 41 unchanged, 1 skipped (deleted here)`, or with `--json` `{"clients": {"created", "updated", "unchanged", "skipped"}, "areas": {…}, "projects": {…}, "entries": {…}}`. With `--dry-run` it prints the same summary and writes nothing.

Import reads only this format. Converters from other trackers are external scripts that write it, deriving every id as a UUID version 5 (RFC 9562) in a namespace of their choosing from names such as `client:<source id>` and `entry:<source id>`, so rerunning on a later dump updates instead of duplicating.

### 3.11 Exit codes

| Code | Meaning |
|---|---|
| 0 | Success; for `check`, no inconsistencies (left) |
| 1 | Other failure (I/O) |
| 2 | Usage error: unknown option, malformed date or color, range too large, missing `--yes`, conflicting options |
| 3 | Named project, area, client, or entry not found, or ambiguous |
| 4 | Refused by a store rule: nothing running, archived project, duplicate name, overlap without `--force`, a time in the future |
| 5 | Store unavailable: missing, locked past the busy timeout, or a newer schema version |
| 6 | `check` found an inconsistency |
| 7 | An input file (description or import) failed to parse or validate |

Errors go to stderr as one line starting with `error:`, or with `--json` as `{"error": {"code": 3, "message": "…", "candidates": [...]}}`. On error stdout stays empty.

## 4. The description file and `check`

The description file states which clients exist, their areas and colors, and the standing projects that must be active in each area. The command `check FILE [--client NAME] [--fix] [--strict]` prints one line per difference from the store; a matching store prints nothing and exits 0.

### 4.1 Format

TOML; a JSON file of the same structure is accepted too.

```toml
version = 1

[[client]]
name = "University"

  [[client.area]]
  name = "Research"
  color = "#0A9396"
  projects = ["Noise paper", { name = "Grant renewal" }]
```

A standing project is a name or an equivalent table `{ name = "…" }`. An area named like its client is the general area. Validation (exit 7): `version` equals 1; each client has `name` and at least one `area`; each area has `name`, a `#RRGGBB` `color` (either case), and a `projects` array; a project table has only `name`; names are unique per the store's rules (clients globally, areas within a client, projects within a client), compared after trimming, case- and diacritic-insensitively.

### 4.2 Rules

Violations print in rule order, then alphabetically. With `--client`, only that client is examined.

| # | Rule | Report line |
|---|---|---|
| 1 | Clients in the file exist | `missing client: Personal` |
| 2 | Listed areas exist and are not retired | `missing area: Personal / Health`, `retired area: Personal / Health` |
| 3 | Colors match (case-insensitively) | `color mismatch: University / Research is #2A9D8F, expected #0A9396` |
| 4 | Standing projects exist, active, in their listed area | `missing project: University / Research / Grant renewal`, `archived project: University / Teaching / Grading`, `wrong area: University / Noise paper is in Teaching, expected Research` |
| 5 | Active projects belong to a listed area | `unlisted area: Personal / Garden (active projects: Fence, Pond)` |
| 6 | Clients with an active project are listed | `unlisted client: Side business (active projects: 3)` |
| 7 | With `--strict`: active projects in a listed area are listed | `unlisted project: University / Teaching / Grading` |

Rule 7 reports each active project in a listed area whose name no area of its client lists (a project listed under another area is rule 4's `wrong area`). The file then states every active project, so a generator can list each area's standing projects together with the projects another system keeps open, and one strict check finds both sides' differences. Unlisted areas without active projects are never reported. With `--json`: `{"inconsistencies": [{"rule", "kind", "client", "area", "project", "actual", "expected", "message"}]}`, where `kind` is the report line's label with hyphens (`missing-client`, `color-mismatch`).

### 4.3 `check --fix`

In one transaction and in this order, `--fix` creates missing clients (with their general area, colored from the file if listed), creates missing areas, recolors areas, un-retires listed areas, unarchives standing projects, and creates missing standing projects, printing one line per action: `created client: Personal`, `created area: Personal / Health #AE2012`, `recolored area: University / Research from #2A9D8F to #0A9396`, `unretired area: Personal / Garden`, `unarchived project: University / Teaching / Grading`, `created project: University / Research / Grant renewal`.

It does only what loses no information: it never archives, moves, renames, or deletes, so rule 7's projects stay as they are. Remaining violations print afterwards as in a plain check; exit 6 if any remain, else 0. With `--json`: `{"actions": [{"kind", "client", "area", "project", "message"}], "inconsistencies": [...]}`, with kinds like `created-client` and `recolored-area`.

## 5. App Intents

The intents live in the library and both apps include them; the phrase table and the wrapper intents of widget and control buttons are in [ios.md](ios.md) §6. Every intent runs in the background except `ShowTimerIntent`. They call the same library operations as the tool, and its exit-4 refusals become thrown errors with the same messages. No intent deletes, archives, or edits.

Entities are identified by the record's UUID, and their property names match the JSON records of section 3. Projects are found by name (prefix, then substring) and by state, client, and area, suggested as active projects by recency, and archived ones appear only when asked for. Areas are found by name or enumerated, clients enumerated, and time entries found by identifier only.

| Intent | Parameters | Result |
|---|---|---|
| `StartTimerIntent` | `task?`, `project?`, hidden `inferProject` (default false) | The entry, dialog "Started Clarify noise model on Noise paper."; stops a running entry. Only the Siri App Shortcut sets `inferProject` ([ios.md](ios.md) §6.3): with a non-empty task and no project, it assigns the project of the most recent entry whose task equals the task (trimmed, case- and diacritic-insensitively) and whose project is active, else none |
| `StopTimerIntent` | none | The stopped entry with its duration in the dialog; nothing running returns nil with "Nothing is running." (not an error) |
| `ContinueIntent` | `project?` | The new entry: from the most recent entry other than the running one, or the project's most recent |
| `CurrentEntryIntent` | none | The running entry or nil |
| `TodayTotalIntent` | `date?` (today) | That shown day's total as a duration, including the running entry, dialog "4 hours 2 minutes today" |
| `EntriesIntent` | `from`, `to`, `project?`, `client?` | Entries of the half-open range of days, as `entries`; a `to` not after `from` means that one day |
| `CreateProjectIntent` | `name`, `area` | The project; fails as `project create` |
| `ShowTimerIntent` | none | Opens the Mini Timer (Mac) or the Timer tab |

## 6. URL scheme

Both apps handle `timetracking` (`timetracking-debug` in Debug). URLs act in the order they arrive: on the Mac each waits for the one before.

| URL | Action | Platform |
|---|---|---|
| `timetracking://start?project=NAME&task=TEXT` | Start an entry (both optional; `project_id=<uuid>` is the exact form), stopping the running one | Mac, iOS |
| `timetracking://stop` | Stop the running entry | Mac, iOS |
| `timetracking://continue` | Continue the most recent entry | Mac, iOS |
| `timetracking://show` | Show the Mini Timer (Mac) or the Timer tab | Mac, iOS |
| `timetracking://planner/calendar?date=2026-10-29` | Calendar on that day (default today) | Mac, iPad |
| `timetracking://planner/reports?from=2026-10-19&to=2026-10-26` | Reports on that range (`to` exclusive) | Mac, iPad |
| `timetracking://planner/projects` | Projects section | Mac, iPad |
| `timetracking://planner/activity?date=2026-10-29` | Activity section | Mac, iPad |
| `timetracking://project/<uuid>` | The project in Projects (also a time block's link) | Mac, iPad |

A project name that is unknown, archived, or ambiguous starts nothing and shows an alert naming the problem (titled "Couldn't Open the Link" on the Mac, "Can't Open This Link" on iOS); URLs never create projects. Any other host or path shows "This link isn't one the app understands." On the Mac, `start`, `stop`, and `continue` do not activate the app, whatever the Mini Timer settings say (feedback is the menu bar and, if permitted, a banner "Started Noise paper"); on iOS the app shows the Timer. On the iPhone, `planner/*` and `project/` URLs open the Timer. Values over 1,000 characters are rejected with an alert. Universal links are not used.

## 7. Read-only access for scripts

The store is `~/Library/Group Containers/<TEAM>.<APP_ID>/Library/Application Support/TimeTracking/store.sqlite`; `timetracking --store-path` prints it. Scripts open it read-only (`sqlite3 "file:$(timetracking --store-path)?mode=ro"`), never use `immutable=1` on the live file, wrap several queries in one transaction, and never write. The stable surface is defined in [data_and_sync.md](data_and_sync.md) §2.1. The system asks once per program without the App Group entitlement before it may open the container.

## 8. Formats

Reports and the tool use the same writers.

### 8.1 Conventions

Listings and CSV use ISO 8601 timestamps with the system zone's offset at that instant (`2026-10-29T09:15:00+01:00`), dates `YYYY-MM-DD`, durations in integer seconds, lowercase UUIDs, `#RRGGBB` colors, and `null` (JSON) or an empty field (CSV) for no value. CSV follows RFC 4180: comma, quoting with doubled quotes, header row, UTF-8 without BOM, LF.

### 8.2 CSV

Entries CSV (`entries --csv`, `export --format csv`, Reports "Entries (CSV)"):

```
start,stop,seconds,client,area,project,task,running
2026-10-29T09:15:00+01:00,2026-10-29T10:06:30+01:00,3090,University,Research,Noise paper,Clarify noise model,false
```

The running entry has an empty `stop`, `running` `true`, and its elapsed seconds.

Breakdown CSV (`report --csv`, Reports "Breakdown (CSV)"): one column per level in order, then `seconds`, `duration` (`h:mm:ss`), `share` (percent of the range total, one decimal), `entries`; one row per leaf of the fully expanded tree.

Structure tables (tool only): `projects.csv` with `id,name,state,client,area,color,created_at,archived_at,area_id,client_id`; `areas.csv` with `id,name,color,retired,client,client_id`; `clients.csv` with `id,name`.

## 9. Testable behaviors

The tool tests build the Debug tool, create a fixture store from a JSON export, run the tool with `TIMETRACKING_STORE` and `TIMETRACKING_NOW` `2026-10-29T10:00:00` local time (a Thursday), and check stdout, stderr, and exit code.

1. Running `status --json` with an entry running for 1812 seconds prints `running.duration` 1812 and `running.end` null; with nothing running, `"running": null`; both exit 0.
2. Running `start "Task" --project "Noise paper"` while an entry runs stops it at the new start, prints one line naming both, and leaves exactly one running entry.
3. Running `start "Clarify noise model"` when the latest entry with that task has a project creates an entry with no project.
4. Running `start --project "Old paper"` (archived) exits 4; `start --at 2026-10-29T10:05` exits 4; `stop` with nothing running exits 4; none writes anything.
5. Running `start --project Admin` where two clients have an active "Admin" exits 3 listing both; `start --project University/Admin` succeeds; `--project "noise PAPER"` and a diacritic variant of a name match the project.
6. Running `continue` creates a new entry with the task and project of the latest non-running entry and leaves that entry's end unchanged.
7. Running `entries` without a range lists exactly the entries starting on 2026-10-29; `report --json` without a range has `from` `2026-10-26` and `to` `2026-11-02`.
8. Running `entries --from 2026-10-20 --to 2026-10-27 --json` returns exactly the entries starting in that half-open range, ascending, with `total` equal to the sum of their durations.
9. Running `entry create "T" --start 2026-10-20T23:30 --end 2026-10-21T00:30` creates and prints one entry, listed under the day of its start.
10. Running `entry edit` with a change that overlaps another entry exits 4 and changes nothing; with `--force` it succeeds.
11. Running `entry delete ID` without `--yes` prints the entry, exits 2, and deletes nothing; with `--yes` the entry is gone.
12. Running `report --week 2026-W43 --granularity day --group-by project --json` equals the library's report query row for row; `periods` has seven items; `total` equals the sums of `periods` and of `rows`; no row has duration 0.
13. Running `report --week 2026-W44 --granularity day --json` lists 2026-10-30 to 2026-11-01 with duration 0.
14. Running `projects --json` lists active projects by default, archived with `--archived`, both with `--all`; `clients --json` is sorted by name.
15. Running `project create X --area Research` exits 4 when an active or archived X exists in the client and succeeds when X exists only in another client.
16. Running `project archive`, `unarchive`, `rename`, or `move` changes only the stated fields, and the project's entry ids are unchanged.
17. Running `area set-color Research --color #3d5a80` shows `#3D5A80` for its projects in `projects --json`; `--color teal` and `--color "#3d5a8"` exit 2.
18. Running `area create Garden --client Personal` without `--color` uses the library's default color; `area rename Personal Home --client Personal` exits 4.
19. Running `check` on a matching file prints nothing and exits 0.
20. Running `check` on a file with a wrong color, a missing standing project, and an archived standing project prints three lines in rule order and exits 6; `--json` lists kinds `color-mismatch`, `missing-project`, `archived-project`.
21. Running `check` on a file without `version`, with color `teal`, or with a project table key other than `name` exits 7; the `{ name = "…" }` form gives the same result as plain names.
22. An active project in an area absent from the file produces one `unlisted area` line; an unlisted area without active projects produces none.
23. Running `check --fix` on a store with a missing client, a recolored area, an archived standing project, and a standing project in the wrong area prints three action lines, then the `wrong area` line, and exits 6; a following `check` prints only `wrong area`; nothing was archived or moved.
24. Exporting the fixture, importing it with `--include-settings` into an empty store, and exporting again yields a document equal to the first except `generatedAt` and `storeID`.
25. Importing the same file twice reports every record unchanged on the second run, appends no outbox row, and posts no change notification.
26. An import whose record id is a tombstone in the store reports it skipped and keeps the tombstone; a record carrying `deletedAt` leaves the store's live record in place ([data_and_sync.md](data_and_sync.md) §5.2).
27. An import with an `areaID` found neither in the file nor in the store, or a new project whose name collides with another project of the same client, exits 7 and writes nothing.
28. Running `import --dry-run` prints the same summary as the real import and leaves the store's modification time unchanged.
29. Running `export --from 2026-10-01` or `export --what entries` without `--format csv` exits 2.
30. Running `export --format csv --what entries` writes the Entries CSV of 8.2 with LF endings, RFC 4180 quoting of a task with a comma and a quote, and the running entry's empty `stop`.
31. Running `report --csv --granularity total --group-by client,area,project` writes the header `client,area,project,seconds,duration,share,entries` and is byte-identical to the Reports Breakdown export for the same range, levels, and filters (with `--health` when Reports count health time).
32. A write command waiting on another process's 2-second write transaction succeeds; with a 10-second lock it exits 5.
33. A successful write command posts `<APP_ID>.changed` once and appends one outbox row per changed record; a failed one does neither.
34. Every read command succeeds on a store in a read-only directory and leaves its modification time unchanged.
35. A store whose `meta.schema_version` is one higher than the tool's exits 5 naming both versions.
36. Passing `--json` with `--csv` exits 2, and stdout is empty on every error.
37. The output of `--generate-completion-script zsh` contains every subcommand of 3.4.
38. (App) Opening `timetracking://start?project=Noise%20paper&task=Hello` while the Mac app runs starts that entry without activating the app; `?project=Nonexistent` starts nothing and shows an alert; `timetracking://delete` shows "This link isn't one the app understands."
39. (App) `StopTimerIntent` with nothing running returns nil and "Nothing is running." without throwing; `StartTimerIntent` with an archived project throws the tool's exit-4 message; without `inferProject` it never infers a project.
40. (App) After the tool starts an entry while the Mac app runs, the menu bar shows it within 1 second.
41. Running `entries --from 2026-10-28T09:30 --to 2026-10-29T09:00 --json` lists exactly the entries starting in that interval of instants, with `from` `2026-10-28T09:30:00+01:00` and `to` `2026-10-29T09:00:00+01:00`; `report` over the same bounds totals those entries; a `--to` before the `--from` exits 2.
42. Running `entries --from -3d --json` exits 0 with `from` `2026-10-26`; `--day -1d` and `report --week -1w` resolve likewise.
43. With sleep shown and mapped to an area, `report --day 2026-10-28 --json` leaves the night out and `--health` adds its part of that day as the project "Sleep"; over instant bounds the library's report cuts it at the bounds.
44. Running `check --strict` on a file that omits an active project of a listed area prints `unlisted project: University / Teaching / Grading` (JSON kind `unlisted-project`, rule 7) and exits 6, while a plain `check` prints nothing; `check --strict --fix` keeps the project active.
45. Running `entries --from today --to tomorrow --json` covers exactly today.
46. With a run (activity and distance), a walk without distance, a night, and an import status in the store, `health --from 2026-10-28 --to 2026-10-29 --json` lists the two workouts with their activity, local start and end, duration, and distance (null for the walk) and `lastImport` with device, time, and kinds; `--kind sleep` lists only the night, an instant `--from` only the walk, `--csv` writes `id,kind,activity,start,end,seconds,distance`; `--kind nap` exits 2; a store without an import status prints `"lastImport": null`.
47. With the start of day at 04:00, at 02:00 `today` is the previous date and `status` sums its parts, `report` over a day cuts entries at 04:00, and `entries` over it lists the stored entries starting in it.
48. Today's Total counts an entry's part on the day, also of an entry that started before the start of day, and agrees with `status`.
49. With the start of day at 09:00, the `entries` table puts an entry at 08:00 on October 29 under "Subtotal 2026-10-28" while its row shows its real date.
