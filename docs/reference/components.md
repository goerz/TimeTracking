# Components

TimeTracking is a personal time tracker for the Mac, iPhone, and iPad. It records what the user works on as time entries, keeps the running entry in sync across all devices within seconds, plans the day next to the calendar, reports on tracked time, and keeps a separate record of where attention went on each device. This document names the components, how they connect, and the rules that cut across them. Each spec below ends with numbered testable behaviors.

| Spec | Component |
|---|---|
| [architecture.md](architecture.md) | Project layout, targets, build system, testing, conventions |
| [data_and_sync.md](data_and_sync.md) | Shared library: entities, store, sync, live updates, query layer |
| [timer.md](timer.md) | Mac main window and main menu, Timer and Mini Timer, Pomodoro, idle detection, reminders, settings window, global shortcuts |
| [menubar.md](menubar.md) | Mac menu bar item and Dock menu |
| [projects.md](projects.md) | The sections of the main window and their router; Projects section; clients and areas; project picker and dialog |
| [calendar.md](calendar.md) | Calendar section; time blocks; calendar events |
| [reports.md](reports.md) | Reports section; date ranges; aggregation; CSV export |
| [activity.md](activity.md) | Activity section: the view of the tracker's logs |
| [activity_tracking.md](activity_tracking.md) | Tracker agent: presence, sources, blocks, logs, exclusions, device collection |
| [ios.md](ios.md) | iPhone and iPad app, widgets, control, intents, device collection |
| [automation.md](automation.md) | Command-line tool, App Intents, URL scheme, import and export, consistency check |
| [design.md](design.md) | Design language: typography, spacing, toolbars, symbols, color, components, app icon |

## Vocabulary

| Term | Meaning |
|---|---|
| Client | Who the work is for. Groups areas. |
| Area | An ongoing part of life or line of work, belonging to exactly one client, with a color (any RGB value) and a manual order within its client. Every client has a general area named like the client. |
| Project | A unit of work inside exactly one area; active or archived. Colors come from the area, and entries store no color, area, or client, so moving a project recolors and regroups its history. |
| Task | The free-text description of a time entry ("Clarify noise model"), autocompleted from earlier entries. |
| Time entry | A tracked interval: start, end (or running), project (optional), task. At most one entry runs at a time, across all devices. An entry is stored whole and can span any number of dates, a forgotten timer included. |
| Piece | An entry's part on one shown day. Display and reports cut entries into pieces; nothing stores them. |
| Midnight | The synced setting for the hour the app's days start, 00:00 by default (see "Days" under Cross-cutting rules). Written lowercase, "midnight" is the real one on the clock. |
| Pomodoro | A count-down display of focus and break phases over the running entry, kept per device. It never starts, stops, or splits entries. |
| Activity block | A contiguous stretch of attention, recorded by the tracker with items at three levels: context, subject, detail. Not a time entry; a source for one. The tracker never assigns projects, so its logs stay a neutral record. |
| Time block | A plan ("write the intro, 9 to 11"): an event in an iCloud calendar, optionally linked to a project, so it reaches every device and calendar app. Informational only. |
| Calendar event | An event from a calendar of the system calendar store that the user chose to show. |

## Architecture

```
┌────────────────────────────── Mac ───────────────────────────────┐
│  TimeTracking.app (not sandboxed)                                │
│   ├─ Main window, Mini Timer, settings (timer.md)                │
│   ├─ Sections: Calendar, Reports, Projects, Activity             │
│   │       (calendar.md, reports.md, projects.md,                 │
│   │        activity.md)                                          │
│   ├─ Menu bar item, Dock menu         (menubar.md)               │
│   ├─ Widget push sender (APNs, key in the Keychain)              │
│   ├─ Contents/Helpers/timetracking    command-line tool          │
│   ├─ Contents/Helpers/tracker-event   event client for the agent │
│   └─ Contents/Library/LoginItems/TimeTrackingAgent.app           │
│                                       (activity_tracking.md)     │
└──────────┬──────────────────────────────────────┬────────────────┘
           │ TimeTrackingCore (static package):   │ block log
           │ model, SQLite store, sync, queries,  │ (append-only files
           │ intents, activity-log reader         │  in iCloud Drive)
           │ (data_and_sync.md)                   │
┌──────────┴──────────────────────────────────────┴────────────────┐
│  iCloud: CloudKit private database (main zone incl. LiveState,   │
│  zone ActivityEvents) + iCloud Drive container (Activity/)       │
│  + iCloud calendar (time blocks)                                 │
└──────────┬──────────────────────────────────────────────▲────────┘
           │                                    APNs widget pushes
┌──────────┴─────────────────────────── iOS (one target) ─┴────────┐
│  TimeTrackingiOS.app (sandboxed)      (ios.md)                   │
│   iPhone: Timer screen · iPad: Timer, Calendar, Reports,         │
│   Projects, Activity tabs                                        │
│   ├─ Widgets extension: widgets, control, widget push handler    │
│   ├─ App Intents extension: Focus filter, log-event intent       │
│   ├─ DeviceActivity monitor extension                            │
│   └─ Safari web extension                                        │
└──────────────────────────────────────────────────────────────────┘
```

One Xcode project, one Swift package (`TimeTrackingCore`) linked statically into every executable, and a Makefile that builds, installs, and tests. The package holds the data model, persistence, sync, reporting queries, App Intents, and the reader for the tracker's logs, so the running entry, project list, and reports agree on every device. User interface targets hold views, view state, and platform glue. All identifiers derive from one bundle id; Debug builds carry a `.debug` suffix and have their own containers.

## The components

### Shared library, data model, and sync

Spec: [data_and_sync.md](data_and_sync.md)

The entities and their invariants, the store, sync, live updates, JSON export and import, and the query layer. The store is a documented SQLite schema in the App Group container, with a public `entries` view for scripts. CloudKit sync runs in the app processes, with record-level last-writer-wins and an invariant pass after every change. A `LiveState` record carries the running entry and the Mac's current activity, and the Mac sends WidgetKit pushes itself, without a server, so iPhone and iPad widgets follow within seconds even with the app suspended. The only files in iCloud Drive are the tracker's block log and settings.

### Mac app: main window and Mini Timer

Spec: [timer.md](timer.md)

One main window with a sidebar of Timer, Calendar, Reports, Projects, and Activity (⌘1 to ⌘5). The Timer is the running-entry bar with the recent entries grouped by day. The Mini Timer is the same bar and list in a small window that can shrink to the bar and float above other windows. The spec also covers Pomodoro, idle detection, reminders, the settings window, and global shortcuts. The Timer creates entries only by starting them; past intervals are drawn in the Calendar.

### Mac app: sections

The sidebar items after the Timer. The shell and the hand-offs between sections are in the Projects spec. Reports and Activity share one date range.

- Projects: [projects.md](projects.md). A table of projects with clients and areas, and the project dialog and picker that the Timer, Calendar, and iOS reuse.
- Calendar: [calendar.md](calendar.md). Days side by side, each with up to three columns: activity, tracked, and calendar. Entries are drawn, moved, resized, split, and edited in place, never in the future, and can be made from a block, time block, or event.
- Reports: [reports.md](reports.md). Summary tiles, a stacked chart, a breakdown of up to four levels, an entry list, and CSV export over a date range.
- Activity: [activity.md](activity.md). The tracker's record over a date range. The view never edits the logs.

### Mac app: Menu bar item

Spec: [menubar.md](menubar.md)

A status item showing the running time or Pomodoro countdown, with a menu of the current entry and the main commands; also the Dock icon setting and Dock menu.

### Tracker agent

Spec: [activity_tracking.md](activity_tracking.md)

An opt-in background login item that records where attention goes on the Mac, in blocks, and merges in what iOS collects. It writes an append-only block log to iCloud Drive and local files on the Mac, and never opens the time-entry store. Exclusions apply before anything is written.

### iPhone and iPad app

Spec: [ios.md](ios.md)

One iOS target. The iPhone has the Timer, widgets, a control, App Shortcuts, and device-side activity collection. The iPad has the Timer and the sections as tabs, with touch, Pencil, and keyboard equivalents of the Mac interactions. An iCloud account is required. There is no Mac widget, Apple Watch app, or Live Activity.

### Scripting surface

Spec: [automation.md](automation.md)

The `timetracking` command-line tool, App Intents (Shortcuts, Siri, Spotlight), and the `timetracking://` URL scheme, plus a consistency check against a TOML description of standing projects and import of the JSON export format. Scripts may read the SQLite store through its public views; writes go through the tool.

## Data flow

1. The user starts an entry in any interface. The library stores it, writes `LiveState`, and syncs. The Mac sends a widget push to every iPhone and iPad; open apps receive the change through CloudKit. If two devices start entries while offline, the later start wins and the earlier entry stops at it.
2. The tracker samples attention every 30 seconds, forms blocks, and appends them to the block log. The Mac app reads the log and publishes the current activity into `LiveState`. The iPhone and iPad read the same log without the Mac-only details.
3. In the Calendar, the user makes ordinary entries from blocks, time blocks, and events.
4. Reports and the scripting surface query the store through the same library, and every write goes through its operations.
5. iOS extensions append device events to a staging file; the app flushes them to CloudKit as `DeviceEvent` records; the Mac agent merges them into blocks as a separate source.

## Cross-cutting rules

- Days: entries are stored whole, and the tracker uses real days, so activity blocks close at local midnight. What the app shows and reports (Timer list, Calendar, Reports, Activity, Projects, widgets, the tool's day ranges) follows Midnight ([data_and_sync.md](data_and_sync.md) §8). Display and reports cut entries into pieces at that hour, so daily sums stay plain sums and totals agree, and changing the setting rewrites nothing. Weeks run Monday to Sunday.
- Settings are synced (Midnight, Pomodoro durations, pinned projects, context colors, the Calendar's settings) or per device (idle threshold, shortcuts, menu bar display, window frames).
- Platforms: macOS 27 and iOS and iPadOS 27 only, with no availability checks. The apps are built from source with the Makefile and development-signed (APNs sandbox, CloudKit development environment); there is no App Store or TestFlight distribution.
- Every testable behavior has a test carrying its identifier `<prefix>-<n>` (ARCH, DATA, TM, MB, PP, PC, PR, PA, TRK, IOS, AUTO); `make check-behaviors` enforces the mapping.
- The Mac app, agent, and tools are not sandboxed and share one App Group container; the iOS app and its extensions are sandboxed.
- Privacy: raw activity detail stays on the Mac, only block summaries sync, and exclusions apply before anything is written.
- Every entity is soft-deleted; tombstones sync and are kept 180 days. Durations are rounded only for display.
- Keyboard first on the Mac and iPad: every action has a menu command and, where frequent, a shortcut.
- The Mac and iPad ask for full calendar access for the Calendar section; the iPhone needs none.
