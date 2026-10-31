# Spec: Scripting Surface

This spec covers every way a program other than the app's user interface reads or changes tracked time: the command-line tool `timetracking`, which links the shared library and works on the local store; App Intents defined once in the library and exposed by the Mac and iOS apps to Shortcuts, Siri, and Spotlight; and the `timetracking` URL scheme. It also owns the CSV formats, the description file, and `check`. Everything runs on the device against the local store; there is no web API.

Not included: an AppleScript dictionary, `x-callback-url`, time-block commands (blocks are calendar events, `spec_planner_calendar.md`), an automatic export file, and a status file for prompts.

## 1. Principles

1. Every surface parses input, calls the library, and formats output; none holds business logic.
2. Read commands (`status`, `entries`, `entry show`, `report`, `projects`, `clients`, `areas`, `check` without `--fix`, `export`) open the store read-only and leave no mark.
3. Every listing has a JSON form and, where tabular, a CSV form. Their shapes change only with a format version bump; human-readable tables may change.
4. Scripts refer to projects, areas, and clients by name; every JSON record also carries the UUID.
5. URLs start, stop, continue, and show. Intents never delete. The tool deletes one entry at a time, only with `--yes`.
6. The tool works without the app running.

## 2. Store access

| Surface | Process | Path to the data |
|---|---|---|
| `timetracking` | Its own | The library on the SQLite store in the App Group container |
| App Intents | The Mac or iOS app, launched in the background if needed | The library in the app process |
| URL scheme | The Mac or iOS app | The library in the app process |
| Scripts | Any | The SQLite file, read-only (section 7) |

A read command opens the store with `SQLITE_OPEN_READONLY` and runs all its queries in one read transaction. A write command writes through the library whether or not the app runs; the library's busy timeout, invariant pass, outbox, and the Darwin notification `<APP_ID>.changed` are defined in `spec_data_and_sync.md` §2.2. The tool never touches CloudKit; the app sends its outbox rows and the `LiveState` change.

The tool is embedded at `Contents/Helpers/timetracking` and linked into `PATH` by `make install` (`spec_architecture.md`), so it always matches the installed app.

## 3. The command-line tool

### 3.1 Global options

The invocation is `timetracking <subcommand> [options]`, parsed with Swift Argument Parser: `--help` for every subcommand, no abbreviations, completions from `timetracking --generate-completion-script zsh|bash|fish`. The `ALIAS` setting in `local.mk` adds a second name; there is no default alias.

| Option | Meaning | Default |
|---|---|---|
| `--json` | JSON output | off |
| `--csv` | CSV output (section 8) | off |
| `--store PATH` | Use this store file | the live store |
| `--quiet`, `-q` | No output on success for write commands | off |
| `--no-color` | No ANSI color | on when stdout is not a terminal |
| `--store-path` | Print the resolved store path and exit | |
| `--version` | Print tool and schema versions | |

Global options may come before or after the subcommand. The options `--json` and `--csv` are mutually exclusive. The variable `TIMETRACKING_STORE` acts as `--store` (the option wins). The tool honors `NO_COLOR`. The variable `TIMETRACKING_NOW` (ISO 8601) fixes "now" in Debug builds only. Times are read and printed in the system time zone.

### 3.2 Dates and ranges

Date arguments (`--from`, `--to`, `--day`, `--week`, `--month`, `--at`, `--start`, `--end`) accept `2026-10-29`, `2026-10-29T09:15` (offset optional), `2026-W44`, `2026-10`, the words `today`, `yesterday`, `week`, `last-week`, `month`, `last-month`, `year`, and `-3d`, `-2w`, `-1m`.

Days run midnight to midnight, local time; weeks run Monday to Sunday. The range `--from A --to B` is half-open (`--to` names the first day excluded). The options `--day`, `--week`, and `--month` are shorthands. Defaults: `entries` today, `report` the current week. A range over 366 days is a usage error unless `--all-time` is given. Ranges may include future days.

### 3.3 Names and identifiers

The options `--project`, `--area`, and `--client` take a name, matched after trimming, case- and diacritic-insensitively (the store's uniqueness rules, `spec_data_and_sync.md` §1). An archived project matches only with `--archived`. A project name found in several clients exits 3 and lists the candidates; `--client` or the form `Client/Project` resolves it. The options `--project-id`, `--area-id`, `--client-id`, and `--entry-id` take UUIDs. Output uses lowercase UUIDs and upper-case `#RRGGBB`; input colors accept either case.

A write command prints one line describing the change (`Started "Clarify noise model" on Noise paper at 09:15.`), or with `--json` the changed record; `--quiet` suppresses the line, never an error.

### 3.4 Subcommands

| Subcommand | Writes | Purpose |
|---|---|---|
| `status` | | Running entry, today's total, unsent change count |
| `start`, `stop`, `continue` | yes | 3.5 |
| `entries` | | List entries in a range |
| `entry show\|create\|edit\|delete` | create, edit, delete | One entry |
| `report` | | Totals by group and period |
| `projects`, `clients`, `areas` | | The structure |
| `project create\|archive\|unarchive\|rename\|move` | yes | 3.9 |
| `area create\|rename\|set-color` | yes | 3.9 |
| `client create\|rename` | yes | 3.9 |
| `check` | with `--fix` | Section 4 |
| `import` | yes | 3.10 |
| `export` | | 3.10 |

### 3.5 Status, start, stop, continue

The `status` command prints the running entry (task, project, client, start, elapsed) or `No entry running.`, today's total including the running entry, and the count of unsent local changes. Exit 0 either way. JSON:

```json
{
  "running": {"id": "7b1a…", "start": "2026-10-29T09:15:00+01:00", "end": null, "duration": 1812, "running": true, "task": "Clarify noise model",
              "project": {"id": "5e0c…", "name": "Noise paper"}, "area": {"id": "a1f3…", "name": "Research", "color": "#0A9396"}, "client": {"id": "c9d2…", "name": "University"}},
  "today": {"date": "2026-10-29", "duration": 14532},
  "pendingChanges": 0,
  "asOf": "2026-10-29T09:45:12+01:00"
}
```

The field `running` is `null` when nothing runs. This object (with `running` false and `end` set for a stopped entry; `project`, `area`, `client` null without a project) is the entry record of every listing.

| Command | Effect | Refused with exit 4 |
|---|---|---|
| `start [TASK] [--project NAME] [--at TIME] [--force]` | Starts an entry; stops a running entry at the new start and says so. Never infers a project. `--at` backdates up to 24 hours | `--at` in the future, before the running entry's start, or overlapping a stopped entry (unless `--force`); an archived project (`Project "X" is archived; unarchive it first.`) |
| `stop [--at TIME]` | Stops the running entry (its last midnight piece) | Nothing running (`No entry running.`); `--at` before the start or in the future |
| `continue [--entry-id ID \| --project NAME \| --task TEXT]` | New entry with the task and project of: the most recent entry other than the running one; the given entry; or the most recent match. Stops a running entry first | Continuing the running entry itself |

### 3.6 Entries

The command `entries [range] [--project NAME] [--client NAME] [--area NAME] [--task TEXT] [--no-project] [--running] [--limit N] [--order asc|desc]` lists entries whose start lies in the range, ascending by default. The option `--task` is a case-insensitive substring match; `--running` lists only the running entry regardless of range. Table columns: Date, Start, End, Duration, Project, Client, Task, with a subtotal at each day change. JSON is `{"from", "to", "entries": [entry records], "total"}`, where `total` includes the running entry's elapsed time.

| Command | Effect |
|---|---|
| `entry show ID` | Prints one entry |
| `entry create [TASK] --start TIME --end TIME [--project NAME] [--force]` | Creates a stopped entry |
| `entry edit ID [--start TIME] [--end TIME] [--project NAME \| --no-project] [--task TEXT] [--force]` | Changes one entry |
| `entry delete ID --yes` | Deletes one entry; without `--yes` prints it and exits 2 |

Create and edit refuse with exit 4 an overlap (unless `--force`), an end in the future, and an end before the start. An entry across midnight is split by the store (`spec_data_and_sync.md` §1.5) and every resulting entry is printed. There is no bulk delete.

### 3.7 Report

Synopsis: `timetracking report [range] [--group-by KEYS] [--granularity total|day|week|month] [--hours] [--project NAME] [--client NAME] [--area NAME] [--task TEXT] [--no-project]`

The option `--group-by` is an ordered list of up to four of `client`, `area`, `project`, `task`, `day` (default `client,area,project`); `--granularity` defaults to `total`. The tool calls the library's report query, the one Reports uses. The table has one row per group, one column per period, a Total column, and a totals row; durations print as `h:mm:ss`, or decimal hours with two decimals under `--hours`. JSON:

```json
{
  "from": "2026-10-19", "to": "2026-10-26", "granularity": "day", "groupBy": ["client", "area", "project"],
  "rows": [{"period": "2026-10-20", "client": "University", "area": "Research", "project": "Noise paper", "duration": 7380, "entries": 3}],
  "periods": [{"period": "2026-10-19", "duration": 0}, {"period": "2026-10-20", "duration": 7380}],
  "total": 7380
}
```

Rows with zero duration are omitted; `periods` lists every period including empty and future ones. A row has only the `groupBy` keys (null for entries without a project) plus `duration` and `entries`. The `period` is the first day's date (`day`), `2026-W43` (`week`), `2026-10` (`month`), or `"total"`. With `--csv` the tool writes the Breakdown CSV (8.2); with a granularity other than `total` a first column `period` is added.

### 3.8 Structure listings

The command `projects [--active|--archived|--all] [--client NAME] [--area NAME] [--sort name|client|area|last-entry]` lists projects (default active, sorted by client, area, name). Columns: Project, Client, Area, Color, State, Last entry. JSON: `{"projects": [{"id", "name", "state", "area": {"id", "name", "color"}, "client": {"id", "name"}, "createdAt", "archivedAt", "lastEntryAt"}]}` with `state` `"active"` or `"archived"`.

The command `clients` lists clients alphabetically: `{"clients": [{"id", "name", "areaCount", "activeProjectCount"}]}`. The command `areas [--client NAME] [--retired]` prints `{"areas": [{"id", "name", "color", "retired", "general", "client": {"id", "name"}, "activeProjectCount"}]}`; retired areas only with `--retired`.

### 3.9 Managing projects, areas, clients

| Command | Effect | Refused (exit 4 unless noted) |
|---|---|---|
| `project create NAME --area AREA [--client CLIENT]` | Creates an active project | Name taken by a project of the client (active or archived); area retired |
| `project archive NAME` | Archives; entries keep the project | Already archived |
| `project unarchive NAME` | Restores | Already active |
| `project rename OLD NEW` | Renames | NEW taken |
| `project move NAME --area AREA [--client CLIENT]` | Moves to another area of any client | Target not found (exit 3) |
| `area create NAME --client CLIENT [--color #RRGGBB]` | Creates an area; default color per `spec_data_and_sync.md` §1.2 | Name taken; malformed color (exit 2) |
| `area rename OLD NEW --client CLIENT` | Renames | NEW taken; OLD is the general area |
| `area set-color NAME --color #RRGGBB [--client CLIENT]` | Recolors the area | Malformed color (exit 2) |
| `client create NAME [--color #RRGGBB]` | Creates a client with its general area | Name taken |
| `client rename OLD NEW` | Renames the client and its general area | NEW taken |

There is no command to delete a project, area, or client.

### 3.10 Import and export

The command `export [-o PATH] [--include-deleted]` writes the JSON export (`spec_data_and_sync.md` §5.1) to a file or stdout. The command `export --format csv [range] [--what entries|projects|areas|clients|all] [-o PATH]` writes the Entries CSV (default all time) or a structure table (8.2); with `--what all`, `-o` names a directory receiving `entries.csv`, `projects.csv`, `areas.csv`, and `clients.csv`. A range or `--what` without `--format csv` is a usage error.

The command `import FILE [--dry-run] [--include-settings]` runs the library's import, which validates the whole document, upserts by id in one transaction, and never deletes (`spec_data_and_sync.md` §5.2). A document that fails validation exits 7 with the JSON path and reason, and nothing is written. The option `--include-settings` applies the synced settings (restoring a backup). The tool prints one line per kind, `entries: 1520 created, 3 updated, 41 unchanged, 1 skipped (deleted here)`, or with `--json` `{"clients": {"created", "updated", "unchanged", "skipped"}, "areas": {…}, "projects": {…}, "entries": {…}}`. With `--dry-run` it prints the same summary and writes nothing.

Converters from other trackers write this format. They should derive every id as a UUID version 5 (RFC 9562) in a namespace of their choosing from names such as `client:<source id>` and `entry:<source id>`, so rerunning on a later dump updates instead of duplicating.

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

The description file states which clients exist, their areas and colors, and the standing projects that must be active in each area. The command `check FILE [--client NAME] [--fix]` compares the store with it and prints one line per difference; a matching store prints nothing and exits 0.

### 4.1 Format

TOML (TOMLKit); a JSON file of the same structure is accepted too.

```toml
version = 1

[[client]]
name = "University"

  [[client.area]]
  name = "Research"
  color = "#0A9396"
  projects = ["Noise paper", { name = "Grant renewal" }]

[[client]]
name = "Personal"

  [[client.area]]
  name = "Personal"       # the client's general area
  color = "#6C757D"
  projects = []
```

A standing project is a name or a table `{ name = "…" }` (equivalent). An area named like its client is the general area. Validation (exit 7): `version` equals 1; each client has `name` and at least one `area`; each area has `name`, a `#RRGGBB` `color` (either case), and a `projects` array; a project table has only `name`; names are unique per the store's rules (clients globally, areas within a client, projects within a client), compared after trimming, case- and diacritic-insensitively, as in the check itself.

### 4.2 Rules

Violations print in rule order, then alphabetically. With `--client`, only that client is examined.

| # | Rule | Report line |
|---|---|---|
| 1 | Every client in the file exists | `missing client: Personal` |
| 2 | Every listed area exists under its client and is not retired | `missing area: Personal / Health`, `retired area: Personal / Health` |
| 3 | Every area's color matches (case-insensitively) | `color mismatch: University / Research is #2A9D8F, expected #0A9396` |
| 4 | Every standing project exists and is active in its listed area | `missing project: University / Research / Grant renewal`, `archived project: University / Teaching / Grading`, `wrong area: University / Noise paper is in Teaching, expected Research` |
| 5 | Every active project belongs to a listed area | `unlisted area: Personal / Garden (active projects: Fence, Pond)` |
| 6 | Every client with an active project is listed | `unlisted client: Side business (active projects: 3)` |

Unlisted active projects in a listed area, and unlisted areas without active projects, are not reported. With `--json`: `{"inconsistencies": [{"rule", "kind", "client", "area", "project", "actual", "expected", "message"}]}`, where `kind` is one of `missing-client`, `missing-area`, `retired-area`, `color-mismatch`, `missing-project`, `archived-project`, `wrong-area`, `unlisted-area`, `unlisted-client`.

### 4.3 `check --fix`

In one transaction and in this order, `--fix` creates missing clients (with their general area, colored from the file if listed), creates missing areas, recolors areas, un-retires listed areas, unarchives standing projects, and creates missing standing projects, printing one line per action:

```
created client: Personal
created area: Personal / Health #AE2012
recolored area: University / Research from #2A9D8F to #0A9396
unretired area: Personal / Garden
unarchived project: University / Teaching / Grading
created project: University / Research / Grant renewal
```

It never archives, moves, renames, or deletes. Remaining violations print afterwards as in a plain check; exit 6 if any remain, else 0. With `--json`: `{"actions": [{"kind", "client", "area", "project", "message"}], "inconsistencies": [...]}`, with kinds `created-client`, `created-area`, `recolored-area`, `unretired-area`, `unarchived-project`, `created-project`.

## 5. App Intents

The intents and entities live in the library's `AppIntentsPackage`, which both apps include; the shared phrase table is listed in `spec_ios.md` §6.2. Every intent sets `openAppWhenRun = false` except `ShowTimerIntent`. They call the same library operations as the tool, and the tool's exit-4 refusals become thrown errors with the same messages. Widget and control buttons use wrapper intents defined in `spec_ios.md`.

| Entity | Identifier | Display | Properties | Query |
|---|---|---|---|---|
| `ProjectEntity` | project UUID | name, subtitle "Client · Area", area color | name, state, area, client, lastEntryAt | by name (prefix, then substring), active projects by recency; by state, client, area; archived only when asked |
| `AreaEntity` | area UUID | name, subtitle client | name, color, client | by name; enumerable |
| `ClientEntity` | client UUID | name | name | enumerable |
| `TimeEntryEntity` | entry UUID | task or "No task", subtitle project and start | start, end, duration, running, task, project | by identifier only |

Property names match the JSON records of section 3.

| Intent | Parameters | Result |
|---|---|---|
| `StartTimerIntent` | `task: String?`, `project: ProjectEntity?`, hidden `inferProject: Bool` (default false) | `TimeEntryEntity`, dialog "Started Clarify noise model on Noise paper."; stops a running entry; with `inferProject` set (only the Siri App Shortcut sets it, `spec_ios.md` §6.3), a non-empty task, and no project, assigns the project of the most recent entry whose task equals the task (trimmed, case- and diacritic-insensitively) and whose project is active, else none |
| `StopTimerIntent` | none | The stopped `TimeEntryEntity` with its duration in the dialog; nothing running returns nil with "Nothing is running." (not an error) |
| `ContinueIntent` | `project: ProjectEntity?` | `TimeEntryEntity`: the most recent entry other than the running one, or the project's most recent |
| `CurrentEntryIntent` | none | `TimeEntryEntity?` |
| `TodayTotalIntent` | `date: Date?` (today) | `Measurement<UnitDuration>` including the running entry, dialog "4 hours 2 minutes today" |
| `EntriesIntent` | `from`, `to`, `project?`, `client?` | `[TimeEntryEntity]`, half-open range as `entries` |
| `CreateProjectIntent` | `name`, `area: AreaEntity` | `ProjectEntity`; fails as `project create` |
| `ShowTimerIntent` | none | Opens the Mini Timer (Mac) or the Timer tab |

No intent deletes, archives, or edits.

## 6. URL scheme

Both apps handle `timetracking` (`timetracking-debug` in Debug) with `onOpenURL`. Query values are URL-encoded.

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

A project name that is unknown, archived, or ambiguous starts nothing and shows an alert naming the problem (on the Mac titled "Couldn't Open the Link"); URLs never create projects. Any other host or path shows "This link isn't one the app understands." On the Mac, `start`, `stop`, and `continue` do not activate the app (feedback is the menu bar and, if permitted, a banner "Started Noise paper"); on iOS the app shows the Timer. On the iPhone, `planner/*` and `project/` URLs open the Timer. Values over 1,000 characters are rejected with an alert. Universal links are not used.

## 7. Read-only access for scripts

The store is `~/Library/Group Containers/<TEAM>.<APP_ID>/Library/Application Support/TimeTracking/store.sqlite`; `timetracking --store-path` prints it. Scripts open it read-only (`sqlite3 "file:$(timetracking --store-path)?mode=ro"`), never use `immutable=1` on the live file, wrap several queries in one transaction, and never write. The stable surface (the `entries` view and the `client`, `area`, `project`, and `setting` tables) is defined in `spec_data_and_sync.md` §2.1. The tool exits 5 on a newer `meta.schema_version`. The system asks once per program without the App Group entitlement before it may open the container.

## 8. Formats

The Reports export and the tool use the same library writers.

### 8.1 Conventions

Listings and CSV use ISO 8601 timestamps with the system zone's offset at that instant (`2026-10-29T09:15:00+01:00`), dates `YYYY-MM-DD`, durations in integer seconds, lowercase UUIDs, `#RRGGBB` colors, and `null` (JSON) or an empty field (CSV) for no value. CSV follows RFC 4180: comma, quoting with doubled quotes, header row, UTF-8 without BOM, LF.

### 8.2 CSV

Entries CSV (`export --format csv`, Reports "Entries (CSV)"):

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
9. Running `entry create "T" --start 2026-10-20T23:30 --end 2026-10-21T00:30` creates and prints two entries split at midnight, listed under their own days.
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
26. An import whose record id is a tombstone in the store reports it skipped and keeps the tombstone; a record carrying `deletedAt` leaves the store's live record in place (`spec_data_and_sync.md` §5.2).
27. An import with an `areaID` found neither in the file nor in the store, or a new project whose name collides with another project of the same client, exits 7 and writes nothing.
28. Running `import --dry-run` prints the same summary as the real import and leaves the store's modification time unchanged.
29. Running `export --from 2026-10-01` or `export --what entries` without `--format csv` exits 2.
30. Running `export --format csv --what entries` writes the Entries CSV of 8.2 with LF endings, RFC 4180 quoting of a task with a comma and a quote, and the running entry's empty `stop`.
31. Running `report --csv --granularity total --group-by client,area,project` writes the header `client,area,project,seconds,duration,share,entries` and is byte-identical to the Reports Breakdown export for the same range, levels, and filters.
32. A write command waiting on another process's 2-second write transaction succeeds; with a 10-second lock it exits 5.
33. A successful write command posts `<APP_ID>.changed` once and appends one outbox row per changed record; a failed one does neither.
34. Every read command succeeds on a store in a read-only directory and leaves its modification time unchanged.
35. A store whose `meta.schema_version` is one higher than the tool's exits 5 naming both versions.
36. Passing `--json` with `--csv` exits 2, and stdout is empty on every error.
37. The output of `--generate-completion-script zsh` contains every subcommand of 3.4.
38. (App) Opening `timetracking://start?project=Noise%20paper&task=Hello` while the Mac app runs starts that entry without activating the app; `?project=Nonexistent` starts nothing and shows an alert; `timetracking://delete` shows "This link isn't one the app understands."
39. (App) `StopTimerIntent` with nothing running returns nil and "Nothing is running." without throwing; `StartTimerIntent` with an archived project throws the tool's exit-4 message; without `inferProject` it never infers a project.
40. (App) After the tool starts an entry while the Mac app runs, the menu bar shows it within 1 second.

## 10. Decisions

- The tool writes through the library as one more outbox writer, whether or not the app runs; no XPC service.
- App Intents instead of AppleScript: one definition serves Shortcuts, Siri, and Spotlight on both platforms.
- The tool lives in the app bundle, so tool and app versions never differ.
- Import reads only the product's own JSON; converters are external scripts using UUIDv5 ids.
- The `check --fix` option only does what loses no information; archiving and moving stay explicit.
- The `start` command never infers a project; only the Siri App Shortcut does.
- Listings nest project, area, and client; the export references by id for exact round trips.
- Ranges are half-open, so they compose without an "end of day" ambiguity.

## 11. Interfaces

Assumed of `spec_data_and_sync.md`: the store and its path, WAL, busy timeout, invariant pass, outbox, and `<APP_ID>.changed` (§2.2); the read path for scripts (§2.1); `StoreError` cases mapped to exits 3, 4, and 7; the report, entry, and structure queries; the JSON export and import (§5); the default area color and the general area.

Assumed of `spec_architecture.md`: the `TimeTrackingCLI` target and its entitlement, the `.debug` identity and scheme, `make install`, `TimeTrackingCLITests`.

Provided to `spec_planner_reports.md`: the CSV writers and columns of 8.2; Reports' breakdown levels are a subset of `--group-by`.

Provided to `spec_ios.md`: the intents and entities of section 5, including the `inferProject` rule, and the URL scheme; assumed from it: the phrase table and the wrapper intents.

Provided to `spec_planner_calendar.md`: `timetracking://project/<uuid>` as a block's project link.
