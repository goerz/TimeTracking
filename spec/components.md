# Components

TimeTracking is a personal time tracker for the Mac, iPhone, and iPad. It records what the user works on as time entries (client, area, project, task), keeps the running entry in sync across all devices within seconds, plans the day next to the calendar, reports on tracked time, and keeps a separate record of where attention actually went on each device. This document lists the components, what each owns, how they connect, and the rules that cut across them. Each linked spec ends with numbered testable behaviors, its decisions, and the interfaces it assumes of its neighbors.

| Spec | Component |
|---|---|
| [spec_architecture.md](spec_architecture.md) | Project layout, targets, build system, testing, conventions, implementation order |
| [spec_data_and_sync.md](spec_data_and_sync.md) | Shared library: entities, store, sync, live updates, query layer |
| [spec_timer_window.md](spec_timer_window.md) | Mac Timer window, Pomodoro, idle detection, reminders, settings window, global shortcuts |
| [spec_menubar.md](spec_menubar.md) | Mac menu bar item and Dock menu |
| [spec_planner_projects.md](spec_planner_projects.md) | Planner window shell; Projects section; clients and areas; project picker and dialog |
| [spec_planner_calendar.md](spec_planner_calendar.md) | Planner Calendar section; time blocks; calendar events; suggestion engine |
| [spec_planner_reports.md](spec_planner_reports.md) | Planner Reports section; date ranges; aggregation; CSV export and printing |
| [spec_planner_activity.md](spec_planner_activity.md) | Planner Activity section: the view of the tracker's logs |
| [spec_activity_tracking.md](spec_activity_tracking.md) | Tracker agent: presence, sources, blocks, logs, exclusions, device collection |
| [spec_ios.md](spec_ios.md) | iPhone and iPad app, widgets, control, intents, device collection |
| [spec_automation.md](spec_automation.md) | Command-line tool, App Intents, URL scheme, import and export, consistency check |

## Vocabulary

| Term | Meaning |
|---|---|
| Client | Who the work is for. Groups areas. |
| Area | An ongoing part of life or line of work, belonging to exactly one client. Carries a color (any RGB value) and a manual order within its client. Every client has a general area named like the client. |
| Project | A unit of work inside exactly one area; active or archived. Has no color of its own. |
| Task | The free-text description of a time entry ("Clarify noise model"), autocompleted from earlier entries. |
| Time entry | A tracked interval: start, end (or running), project (optional), task. At most one entry runs at a time, across all devices. Entries never cross midnight; an interval spanning midnight is stored as one entry per day. |
| Pomodoro | A local count-down display of focus and break phases over the running entry. It never starts, stops, or splits entries. |
| Activity block | A contiguous stretch of attention on something, recorded by the tracker with items at three levels: context, subject, detail. Not a time entry; a source for one. |
| Time block | A plan ("write the intro, 9 to 11"): an event in the dedicated time-block calendar, optionally linked to a project. Informational only. |
| Calendar event | An event from a calendar of the system calendar store that the user chose to show. |

## Architecture

```
┌────────────────────────────── Mac ───────────────────────────────┐
│  TimeTracking.app (not sandboxed)                                │
│   ├─ Timer window + settings window   (spec_timer_window.md)     │
│   ├─ Planner window: Projects, Calendar, Reports, Activity       │
│   │                                   (spec_planner_*.md)        │
│   ├─ Menu bar item, Dock menu         (spec_menubar.md)          │
│   ├─ Widget push sender (APNs, key in the Keychain)              │
│   ├─ Contents/Helpers/timetracking    command-line tool          │
│   ├─ Contents/Helpers/tracker-event   event client for the agent │
│   └─ Contents/Library/LoginItems/TimeTrackingAgent.app           │
│                                       (spec_activity_tracking.md)│
└──────────┬──────────────────────────────────────┬────────────────┘
           │ TimeTrackingCore (static package):   │ block log
           │ model, SQLite store, sync, queries,  │ (append-only files
           │ intents, activity-log reader,        │  in iCloud Drive)
           │ suggestion engine                    │
           │ (spec_data_and_sync.md)              │
┌──────────┴──────────────────────────────────────┴────────────────┐
│  iCloud: CloudKit private database (main zone incl. LiveState,   │
│  zone ActivityEvents) + iCloud Drive container (Activity/)       │
│  + iCloud calendar (time blocks)                                 │
└──────────┬──────────────────────────────────────────────▲────────┘
           │                                    APNs widget pushes
┌──────────┴─────────────────────────── iOS (one target) ─┴────────┐
│  TimeTrackingiOS.app (sandboxed)      (spec_ios.md)              │
│   iPhone: Timer screen · iPad: Timer, Projects, Calendar,        │
│   Reports, Activity tabs                                         │
│   ├─ Widgets extension: widgets, control, widget push handler    │
│   ├─ App Intents extension: Focus filter, log-event intent       │
│   ├─ DeviceActivity monitor extension                            │
│   └─ Safari web extension                                        │
└──────────────────────────────────────────────────────────────────┘
```

One Xcode project, one shared Swift package (`TimeTrackingCore`, linked statically) that every executable links, and a Makefile that builds, installs, and tests. The package owns the data model, persistence, sync, the reporting queries, the App Intents definitions, the suggestion engine, and the reader for the tracker's logs. The user interface targets own views, view state, and platform glue. All container identifiers derive from one bundle id; Debug builds carry a `.debug` suffix on both platforms and have their own containers and CloudKit container.

## The components

### Shared library, data model, and sync

Spec: [spec_data_and_sync.md](spec_data_and_sync.md)

Owns the entities (client, area, project, time entry, settings, device), their invariants (one running entry, entries split at midnight, archived projects keep their history, soft deletion with tombstones kept 180 days), the store, synchronization, the live-update path, JSON export and import, and the query layer used by the Timer list, Reports, Calendar, the suggestion engine, and the scripting surface. The store is the product's own documented SQLite schema in the App Group container, read through GRDB, with a public `entries` view for scripts. Sync runs through CloudKit's `CKSyncEngine` in the app processes, with record-level last-writer-wins and an invariant pass after every change; the command-line tool writes to the same SQLite file and an outbox the app drains, and widget buttons write through intents that run in the app process. A `LiveState` record carries the running entry and the Mac's current activity, and the Mac app sends WidgetKit push updates to the iPhone and iPad so their widgets follow within seconds. The only files in iCloud Drive are the tracker's block log and settings. The library also reads the block log on every device and defines the `DeviceEvent` records through which the iOS collection reaches the Mac agent.

### Mac app: Timer window

Spec: [spec_timer_window.md](spec_timer_window.md)

The everyday window: the running-entry bar (task field with autocompletion and the `@` project trigger, project chip, timer, start/stop, Pomodoro button, pin button) above the list of recent entries grouped by day, with a live Today total. Resizing the window below a threshold height leaves only the bar (compact mode). The pin floats the window above other windows. The Pomodoro is display only: the entry runs through focus and break phases, and a long absence is handled by idle detection. Idle detection (default 10 minutes) offers Keep, Discard, Discard and continue, and Split. The window also owns reminders, the settings window (General, Pomodoro, Idle, Reminders, Shortcuts, Tracker), and the global shortcuts (⌥⌘R shows or hides the window; continue/stop is unassigned by default; both recordable). The Timer window creates entries only by starting them; past intervals are drawn in the Calendar.

### Mac app: Planner window

The second window: a sidebar with four sections (⌘1 to ⌘4; Window > Planner ⌥⌘P). It is not opened at launch. The shell, its restoration, and the hand-offs between sections are specified in the Projects spec. Reports and Activity share one date range.

- Projects: [spec_planner_projects.md](spec_planner_projects.md). A table of projects with area color, client, area, state, created, last tracked, and total tracked; grouping, sorting, filters, and an Active/Archived/All selector; creating, editing, archiving, restoring, and deleting projects without entries; the Clients & Areas view (⌥⌘1) with the system color picker for area colors. Defines the project dialog and the project picker reused by the Timer window, Calendar, and iOS.
- Calendar: [spec_planner_calendar.md](spec_planner_calendar.md). One to seven days side by side with vertical and horizontal zoom and Today (⌘T). Each day has up to three columns: activity (blocks from the tracker, including iPhone and iPad), tracked (always shown), and calendar (time blocks plus events from selected calendars). Entries are drawn, moved, resized, split, and edited in place, never in the future; overlaps are resolved by a trim/allow/cancel choice. Entries can be made from an activity block, a time block, or a calendar event, and Fill Day proposes entries for all untracked blocks of a day. The suggestion engine (rules plus a weighted nearest-neighbor model, on device) proposes projects and tasks from the tracker's items, calendar titles, time of day, and the previous project, and learns from accept, edit, and skip feedback.
- Reports: [spec_planner_reports.md](spec_planner_reports.md). Date range with presets and period arrows, filters, summary tiles, a stacked bar chart in area colors, a breakdown table of up to four levels (client, area, project, task, day), an entry list that opens the shared editor, CSV export, and printing.
- Activity: [spec_planner_activity.md](spec_planner_activity.md). The tracker's record rendered for a date range: active time per device, context chips, a heatmap by hour, stacked bars by day and context, ranked contexts with their subjects and (on the recording Mac) details, background work, away periods, and the tracker's health. Context colors are assigned automatically and synced. The view never edits the logs.

### Mac app: Menu bar item

Spec: [spec_menubar.md](spec_menubar.md)

A status item showing the running time (or the Pomodoro countdown with its own glyph), optionally the project name, and a menu with the current task and project, New ⌘N, Continue ⌘O, Stop ⌘S, the pending Pomodoro confirmation, Show Timer Window (⌥⌘R), Open Planner ⌥⌘P, Settings ⌘,, and Quit ⌘Q. It owns the "Show Dock icon" setting and the Dock menu, and warns when the tracker is not running.

### Tracker agent

Spec: [spec_activity_tracking.md](spec_activity_tracking.md)

A background login item (`TimeTrackingAgent.app`, not sandboxed) that records where attention goes on the Mac, in blocks, with terminal sessions, browser sites, and documents resolved to the level that identifies the work. It never assigns projects and never opens the time-entry store. It writes an append-only block log in the iCloud Drive container, a local current-state file, a Mac-only detail log, and a health status, and accepts events and rewrite commands over a Unix socket. It merges the `DeviceEvent` records collected on iOS into blocks. Its TOML settings file, including the exclusions that apply before anything is written, is edited in the settings window's Tracker pane, which also shows health and the onboarding checklist. Tracking is opt-in: the agent is registered only when the user enables it in that pane.

### iPhone and iPad app

Spec: [spec_ios.md](spec_ios.md)

One iOS target. On the iPhone: the Timer (start, stop, continue, the shared picker and project dialog as sheets, the recent list, the entry editor, the Pomodoro), widgets for the running entry (Stop), recent entries (Continue), and pinned projects (Start), including Lock Screen families, a Control Center control and Action button action, App Shortcuts over the library's intents, the URL scheme, and the device-side activity collection (DeviceActivity threshold ladder, Focus filter, a log-event intent for Shortcuts automations, a Safari web extension). Widgets update within seconds through the Mac's widget pushes. On the iPad: the Timer as the first tab, then Projects, Calendar, Reports, and Activity tabs equivalent to the Planner sections, with touch, Pencil, and hardware-keyboard equivalents of the Mac interactions. An iCloud account is required.

### Scripting surface

Spec: [spec_automation.md](spec_automation.md)

Every way a program other than the app's own interface reads or changes tracked time: the `timetracking` command-line tool embedded in the Mac app and linked into the PATH by `make install` (status, start, stop, continue, entries, entry, report, projects, clients, areas, management commands, check, import, export; tables, JSON, and CSV), App Intents defined once in the library and exposed on the Mac and iOS (Shortcuts, Siri, Spotlight), and a `timetracking://` URL scheme (nothing destructive). The consistency check compares the store with a TOML description of clients, areas with colors, and standing projects, and `check --fix` creates what is missing. Import reads the product's own JSON export format, which is the path for bringing in history from elsewhere through external converter scripts. Scripts may read the SQLite store read-only through its public views; writes go through the tool.

## Data flow

1. The user starts an entry in any interface (Timer window, menu bar, iPhone, widget, control, intent, command line). The library stores it, writes `LiveState`, and syncs. The Mac app sends a widget push to every iPhone and iPad, whose widgets fetch `LiveState` and show the new entry within seconds, even with the app suspended; open apps receive the change through CloudKit. If two devices start entries while offline, the later start wins and the earlier entry stops at the later start.
2. The tracker samples attention every 30 seconds, forms blocks, and appends them to the block log in the iCloud Drive container. The Mac app reads the log and the local current-state file through the library, and publishes the current activity into `LiveState`. The iPad and iPhone read the same log without the Mac-only details.
3. The Calendar proposes entries from activity blocks, time blocks, and calendar events. Accepting a suggestion creates an ordinary entry; feedback is stored and synced.
4. Reports and the scripting surface query the store through the same library; every write goes through the library's operations.
5. The iOS collection extensions append device events to a staging file in their App Group; the app flushes them to CloudKit as `DeviceEvent` records; the Mac agent reads them through the library and merges them into blocks as a separate source.

## Cross-cutting rules

- Current platforms only: macOS 27, iOS and iPadOS 27, Xcode 27, Swift 6 with complete strict concurrency, SwiftUI with Observation, AppKit or UIKit only where SwiftUI has no equivalent. No availability checks for older systems.
- A paid Apple Developer Program membership is assumed. The apps are built and installed from source with the Makefile and are development-signed (APNs sandbox, CloudKit development environment); there is no App Store or TestFlight distribution. Family Controls uses the development entitlement.
- Every explicitly specified behavior is backed by a test. Each spec numbers its testable behaviors continuously; tests carry the identifier `<prefix>-<n>` (ARCH, DATA, TW, MB, PP, PC, PR, PA, TRK, IOS, AUTO), and `make check-behaviors` enforces the mapping.
- The Mac app, the agent, and the command-line tools are not sandboxed and share one App Group container; the iOS app and its extensions are sandboxed.
- Privacy: raw activity detail stays on the Mac; only block summaries sync; exclusions apply before anything is written; the suggestion engine runs on device.
- Days start at midnight, local time, everywhere: the Timer list, Calendar, Reports, Activity, and the tracker. There is no setting for it. Weeks run Monday to Sunday.
- Every entity is soft-deleted; tombstones sync and are kept 180 days. Durations are never rounded outside display code.
- Keyboard first on the Mac and iPad: every action has a menu command and, where it is frequent, a shortcut. Timer window ⌥⌘R (global, recordable), Planner ⌥⌘P, Planner sections ⌘1 to ⌘4, Clients & Areas ⌥⌘1, Today in Calendar ⌘T, compact Timer mode ⇧⌘M, New ⌘N, Continue ⌘O, Stop ⌘S.
- Calendar access (EventKit full access) is requested by the Mac and iPad apps for the Calendar section; the iPhone needs none.

## Decisions

- One shared library rather than per-app models, so the running entry, project list, and reports agree on every device.
- The product's own SQLite schema (GRDB) with `CKSyncEngine`: unique constraints, custom merge, SQL aggregates for reports, and a documented on-disk format for scripts.
- The tracker never maps activity to projects; the suggestion engine does, so the tracker's logs stay a neutral record and the mapping can be retrained.
- Areas carry the colors; projects do not. Entries store no color, area, or client; display resolves them through the project's current area, so moving a project recolors and regroups its history.
- Entries are split at midnight in storage, so every daily sum is a plain sum and list and report totals agree.
- Time blocks are events in an iCloud calendar of the system calendar store: they sync to every device without extra code, appear in every calendar app, and can be created by any calendar tool. The app reads them but does not manage them.
- Live updates go through CloudKit plus WidgetKit pushes sent by the Mac itself (no server, no LAN connection), so the phone's widgets follow the Mac within seconds while the app is suspended.
- Pomodoro state is device-local on every platform.
- The iPad shares the iOS target and gets the Planner sections as tabs; the Mac keeps two windows. No Mac widget, no Apple Watch app, no Live Activity.
- Settings are either synced (Pomodoro durations, pinned projects, context colors, the time-block calendar, the Calendar's snapping and suggestion options) or per device (idle threshold, shortcuts, menu bar display, window frames, shown calendars).
