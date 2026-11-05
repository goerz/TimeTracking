# Spec: iPhone and iPad App

One iOS target runs on iPhone and iPad. The iPhone gets the Timer in pocket form, widgets, a Control Center control, App Shortcuts, and Siri; the other sections need the width. On the iPad the Timer is the first tab, followed by Calendar, Reports, Projects, and Activity tabs that present the Mac's sections. The target also hosts the device-side activity collection ([spec_activity_tracking.md](spec_activity_tracking.md) §6.2).

This spec states only what differs on a touch device. The Timer is that of [spec_timer.md](spec_timer.md), the picker and project dialog those of [spec_projects.md](spec_projects.md), and the intents, entities, and URL scheme those of [spec_automation.md](spec_automation.md). iOS has no Apple Watch app, Live Activities, idle detection, or "remind me to track time" reminders.

Days shown here (the Timer list, widget totals, Today's Total, the iPad's sections) run from Midnight to Midnight, the synced setting of [spec_data_and_sync.md](spec_data_and_sync.md) §8; entries stay stored split at real midnight.

## 1. Processes

| Process | Target | Owns |
|---|---|---|
| App | `TimeTrackingiOS` | Screens, sync, notifications, the push token upload, the collection flush |
| Widget extension | `TimeTrackingWidgets` | Widgets, controls, the widget push handler |
| App Intents extension | `TimeTrackingIntents` | The Focus filter and `LogActivityEventIntent` |
| DeviceActivity monitor | `TimeTrackingMonitor` | Appending ladder events |
| Safari web extension | `TimeTrackingWebExtension` | Appending browsing events |

All five share the App Group `group.<APP_ID>`; the app and the widget extension also use the iCloud container `iCloud.<APP_ID>`.

Only the app process writes entries. Widget and control buttons run thin wrapper intents (6.1) there, so the change is sent at once; they conform to `LiveActivityIntent` for that reason only, because WidgetKit then launches the app in the background to perform them. The widget extension opens the store read-only and writes only to the App Group. The App Intents extension and the collectors never open the store; they append to the collection file (9.1). The app opens its store and sync engine once per process, even when the iPad restores several windows.

## 2. iPhone: the Timer screen

### 2.1 Layout

Under the large title "Timer" and a settings button, one list holds the running-entry card, the Mac activity line (2.3) and sync pill as its footer, the Siri tip until dismissed, and the recent list (2.6). The search field in the navigation bar's drawer (pull down, or ⌘F) filters as the Mac Timer's ⌘F does ([spec_timer.md](spec_timer.md) §3). There is no tab bar, calendar view, or manual mode.

### 2.2 The running-entry card

The Mac Timer's running-entry bar ([spec_timer.md](spec_timer.md) §2) in three rows: the task field; the project chip; and the Pomodoro button (2.8), the elapsed time, Discard while running, and Start or Stop.

While nothing runs the time reads `0:00:00`, and Start (or Return in the task field) starts an entry with the field's task and the chip's project. While an entry runs the time counts from the chain's start ([spec_data_and_sync.md](spec_data_and_sync.md) §1.5), also during a Pomodoro, and a tap on it opens the edit sheet (2.7). Stop blanks the field and chip. Discard asks as on the Mac and is undoable until the next change.

Starting while another entry runs, from any surface, stops it at the new start. Task field behavior is that of [spec_timer.md](spec_timer.md) §2.2; up to four suggestions appear in the card under the field.

### 2.3 The Mac's current activity

Each Mac whose `LiveState` part has `agentRunning` true ([spec_data_and_sync.md](spec_data_and_sync.md) §4.1) gets a line under the card, at most two, most recently updated first: the device, the primary item's context and subject, and the presence ("MacBook · paper (tmux) · draft"; the subject alone when the context is a plain app name). The presence is omitted while the Mac is in use with input, else "in use", or "idle", "locked", "asleep", or "another user" with "since 14:02". On the iPad, a tap opens the Activity tab.

### 2.4 Project picker and quick creation

The picker appears as a resizable sheet from the chip or the `@` trigger. "Create Project" pushes the project dialog, and its "New Area…" the area form, inside the same sheet; choosing or creating a project assigns it and closes the sheet.

### 2.5 Archived projects

Continuing an entry whose project is archived shows the Mac Timer's alert ("Restore Project and Continue", "Cancel"). Such a row shows the project name in the secondary color.

### 2.6 The recent list

Grouping, day totals, paging, and row content are those of [spec_timer.md](spec_timer.md) §3. The running entry is the first row of Today, with its live duration in the accent color and no continue button or swipes; its long press offers Edit, Copy Task, and Discard. On other rows a tap opens the edit sheet, ▶ or a full leading swipe continues, a trailing swipe deletes after the Mac's confirmation (undoable until the next change), and a long press offers Continue, Edit, Copy Task, and Delete.

### 2.7 Entry editing

A sheet with the task field (the card's autocompletion, no `@` trigger; a suggestion fills the task and project, which Done stores), the project chip, Start and End pickers, the duration, Continue and Delete, and "Created on <device name>". It always edits the stored entry, also from a row that shows part of one. For the running entry End reads "Running", Continue is absent, and only Start, task, and project change. Opening it first stores a task still being typed on the card; Done writes only the fields the sheet changed, so a task stored meanwhile is kept.

The rules and messages of [spec_timer.md](spec_timer.md) §4.2 and §4.3 are checked on Done. An interval crossing real midnight shows "Will be saved as 2 entries, split at midnight", whatever the Midnight setting.

### 2.8 Pomodoro

The Pomodoro is that of [spec_timer.md](spec_timer.md) §5; a tap acts as the Mac's click and a long press opens the menu. It is device-local: one started on the Mac is invisible on the phone, and the reverse. iOS adds:

1. The state is persisted in the device settings at every transition, and a phase's notification (8) is scheduled when it starts.
2. Whenever the app's process runs, it replays that state: a passed phase end becomes the over-state, and if nothing runs the Pomodoro turns off and its notifications are removed. The replay only moves phases, so it never changes an entry.
3. The phase-end sound is the notification's, in the foreground as in the background; with `pomodoro.sounds` off the notification is silent.

### 2.9 Settings

A sheet from the toolbar; longer settings push a screen of their own and show their value in the row.

| Section | Setting | Default | Scope |
|---|---|---|---|
| iCloud | Status, "Waiting to sync", "Device name", "Sync Now" | | Device |
| (none) | Midnight: 00:00 to 23:00 ([spec_data_and_sync.md](spec_data_and_sync.md) §8) | 00:00 | Synced |
| Pomodoro | Focus (1 to 180 min), Break (1 to 60 min) | 25, 5 | Synced |
| Pomodoro | Play a sound when a focus or break ends | On | Device |
| Notifications | "Remind me when an entry runs long", "Remind after" N hours (1 to 12) | On, 4 h; iPad off, so two devices do not remind at once | Device |
| Widgets | "Pinned projects": the ordered `pinnedProjectIDs` | Empty | Synced |
| Widgets | "Task for pinned buttons": "The project's last task" or "No task" | Last task | Device |
| Activity | "Activity collection": the master switch, Screen Time status and request, app groups, setup steps with check marks, "Last sent", "Waiting to send", "Send Now" | Off | Device |
| Activity | "Privacy": a read-only view of the exclusions in `Activity/settings.toml`, edited in the Mac's Tracker pane | | Shared file |
| Apple Health (iPhone) | "Sleep" and "Workouts" ([spec_calendar.md](spec_calendar.md) §6); turning one on asks for access and imports (§7 item 6) | Off | Synced |
| Calendar (iPad) | The Mac's Calendar pane ([spec_calendar.md](spec_calendar.md) §6) | 5 min, no calendars | Synced |
| About | Version and build, the app's Shortcuts link | | |

While notifications are denied, the footer reads "Notifications are off, so focus, break, and reminder alerts won't appear." with "Open Settings".

On screen an app set is an "app group" ([spec_design.md](spec_design.md) §12), with its name and the apps, categories, and sites chosen in the system's picker. Collected activity goes to Activity, so the texts name that, never the log files. A failed send shows "Couldn't send your activity to iCloud. The app will try again." and a refused ladder "Screen Time couldn't start measuring these apps. Try again later."

## 3. Widgets

### 3.1 Common rules

Each timeline is one entry with the policy `.after(date)`: the next Pomodoro phase end when a phase counts down on this device, otherwise the start of the next shown day. Elapsed times are live timers from the chain start, which `LiveState` carries. "Today" is the shown day: its total sums the day's stopped parts and counts the running entry from the later of its own start and the start of the day.

The look is that of [spec_design.md](spec_design.md) §6 and §7 at widget scale, with start and stop circles of 44 pt in Now, 32 pt in Recent rows, and 24 pt as the Pinned stop mark. Outside full-color rendering the circles become one shape with the glyph cut out. Task text is `privacySensitive()`. A widget without content shows "No Pinned Projects" or "No Recent Entries".

A Pomodoro shows as a secondary line under the elapsed time: the phase glyph and the remaining time, or `+` and the time since the phase ended while its confirmation is pending. Tapping outside a button opens the Timer. Smart Stack relevance is 100 while an entry runs, 60 for one hour after one stops, and 10 otherwise; the app donates `StartTimerIntent` for each entry it starts. Buttons require authentication, so nothing changes on a locked device. Before the first sync has delivered the store, every widget shows "Open <app name> to finish setting up".

### 3.2 Running entry widget ("Now")

| Family | Running | Idle |
|---|---|---|
| `systemSmall` | Project; task; Pomodoro line; elapsed time and Stop | "Not tracking"; the latest entry's task and project; "Today" total and Continue |
| `systemMedium` | Task; project and client; elapsed time; live "Today" total and Pomodoro line; Stop; Mac activity footer (2.3) | "Not tracking" and the "Today" total; the latest entry with Continue; Mac activity footer |

### 3.3 Recent entries widget ("Recent")

Families `systemMedium` (3 rows), `systemLarge` (7), and `systemExtraLarge` (two columns of 7). While an entry runs, the first row is that entry with its live time and Stop. The others are the most recent distinct (task, project) pairs, each with a Continue button that starts that pair.

### 3.4 Pinned projects widget ("Pinned")

Shows the synced `pinnedProjectIDs` by default, or an explicit list of 1 to 12 projects, with the task mode from Settings unless configured. Families `systemSmall` (2 buttons), `systemMedium` (4), `systemLarge` (8), and `systemExtraLarge` (12) use a fixed grid, so a family's buttons have one size however many are pinned. A button starts its project; the running project's button takes a light tint of its area color and stops it. An archived project renders disabled with "Archived".

### 3.5 Lock Screen families

| Family | Running | Idle | Button |
|---|---|---|---|
| `accessoryInline` | "12:34 · Project", live | "Not tracking" | None; opens the app |
| `accessoryCircular` | Stop glyph above the live time | Play glyph | Stop, or Continue Latest |
| `accessoryRectangular` | Task, project, live time | "Not tracking", the latest task | Stop, or Continue Latest |

## 4. Live updates

CloudKit cannot send widget pushes and silent pushes are throttled, so widgets follow WidgetKit pushes sent by the Mac plus a direct fetch of `LiveState` ([spec_data_and_sync.md](spec_data_and_sync.md) §4; transport in [spec_architecture.md](spec_architecture.md) §2.4).

1. Push token. The widgets' push handler stores the token, or nil when no widget is installed, in the App Group. The app records it on this device's `Device` record at every wake and fan-out (7), so a lost write repairs itself.
2. Reload. Every widget and control provider fetches `LiveState` (at most 5 s) before building its entry. It reuses the last result when the last fetch returned less than 10 s ago (one push reloads several kinds) or the app wrote the running entry less than 5 s ago. When the running entry changed, it reloads the timer control. The running project's names come from the store when it holds the project, else from `LiveState`.
3. A widget's Stop, or the timer control turned off, on an entry known only from `LiveState` first fetches changes (at most 10 s); if the entry has still not arrived, it fails with "Couldn't reach iCloud. Try again in a moment."
4. Without a running Mac app nothing sends widget pushes. Local changes reload widgets directly; changes from another iOS device arrive through the CloudKit silent push, the next refresh, or the next foreground.

## 5. Control Center control and Action button

The timer control is a toggle whose provider shares the resolver of 4, so it follows a push without its own token. It is on exactly while an entry runs. Its label is the running task (else the project, else "Tracking"), or "Continue" when off. Turning it on continues the most recent entry and off stops the running one, in the app process. It requires authentication. The app reloads it after every change to the running entry, including synced ones.

The "Start Project" control is a button that starts a chosen project with an empty task, for example on the Action button; it covers "always start X", which the toggle does not.

## 6. App Intents, App Shortcuts, Siri, and the URL scheme

### 6.1 Shared and iOS-only intents

The entities and shared intents are those of [spec_automation.md](spec_automation.md) §5; active projects are indexed for Spotlight. iOS adds, hidden from Shortcuts, the wrappers `WidgetStartIntent`, `WidgetStopIntent`, `WidgetContinueIntent`, and `ToggleTimerIntent`, which call the library operations (not a shared intent's `perform()`), send at once, and run the fan-out (7). The App Intents extension holds the Focus filter (9.3) and `LogActivityEventIntent` (9.4), with `label` ("Name") and `kind` ("Type": `appOpened`, `appClosed`, `arrived`, `left`, `chargerConnected`, `chargerDisconnected`, `custom`).

Tracking intents performed before the first sync fail with "Open <app name> once to finish setting up."

### 6.2 App Shortcuts

Both apps share one phrase table, kept in `Shared/` because App Shortcuts are extracted only from an app target. Each phrase ends in "in <app name>" and also exists with "with <app name>", except those that name the app themselves.

| Shortcut | Intent | Phrases |
|---|---|---|
| Start Timer | `StartTimerIntent` | "Start a timer", "Start tracking <project>", "Track <project>", "Start <project>" |
| Stop Timer | `StopTimerIntent` | "Stop the timer", "Stop tracking", "Stop <app name>" |
| Continue | `ContinueIntent` | "Continue", "Resume my last entry", "Continue <project>" |
| What's Running | `CurrentEntryIntent` | "What am I tracking", "What's running", "Is <app name> running" |
| Today's Total | `TodayTotalIntent` | "How much have I tracked today", "<app name> total for today" |
| Show Timer | `ShowTimerIntent` | "Open the timer" |

The app calls `updateAppShortcutParameters()` after every change to the project list, local or synced.

### 6.3 Siri

Project inference is limited to the Start Timer App Shortcut, which sets `StartTimerIntent`'s hidden `inferProject` ([spec_automation.md](spec_automation.md) §5); Shortcuts actions stay literal. When the phrase names no project, Siri asks "What are you working on?" and the answer becomes the task. A name matching two projects is disambiguated by the subtitle "Client · Area"; one matching nothing fails with "I couldn't find a project called X." Today's Total reports the shown day and names any other ("2 hours on Thursday, March 14", with the year when it differs).

### 6.4 URL scheme

The app handles the URLs of [spec_automation.md](spec_automation.md) §6. On the iPad, `planner/*` and `project/` URLs select the matching tab and its state; on the iPhone they show the Timer.

## 7. Sync behavior

1. Wake. The silent-push handler passes the notification to the engine, waits at most 25 s, runs the fan-out, and calls the completion handler exactly once. The app also syncs at every foreground and in a background refresh rescheduled 15 minutes after each run.
2. Offline. Every change commits locally first, so every surface works offline. While the outbox holds changes, a sync pill under the card shows waiting for the network, sending lasting over 10 s, or an error.
3. Adjustments. When the library reports an adjustment to an entry this device created, the Timer shows a banner "Another device changed an entry" with "Show", which opens the edit sheet with a one-line explanation ("Stopped at 10:14 because an entry started on MacBook"). The row keeps a badge until its sheet has opened once. A midnight split shows no banner.
4. Fan-out. After every applied sync and local write, the app reloads widgets and controls, ends the Pomodoro when nothing runs any more, reschedules the long-running reminder, uploads the push token, updates the App Shortcut parameters when projects changed, and flushes the collection file when due (9.6).
5. Midnight. The library's split runs whenever the app's process runs ([spec_data_and_sync.md](spec_data_and_sync.md) §1.5). While an entry runs, the app also wakes at its next real midnight and at the start of the next shown day and runs the fan-out, so the running part moves to the new day. A change of the Midnight setting does the same and reloads the iPad's sections.
6. Apple Health. The iPhone, never the iPad, imports sleep and workouts while `calendar.showSleep` or `calendar.showWorkouts` are on ([spec_data_and_sync.md](spec_data_and_sync.md) §1.9): at every wake after the fetch and when either setting changes in the foreground, then it sends. Only in the foreground does it first ask HealthKit for read access, Workouts including the distance types, so a refresh task never shows the sheet. A failed read (protected data on a locked device) leaves that kind's periods and import time as they were. An import that read at least one kind records the synced import status, at most hourly unless the device or kinds change, which the Calendar settings report.

## 8. Notifications

Local notifications only. Authorization is requested at the first start of an entry on this device; if denied, the Pomodoro confirmation button still works. The Pomodoro's texts and actions are those of [spec_timer.md](spec_timer.md) §10.

| Category | Trigger | Text | Actions | Level |
|---|---|---|---|---|
| `pomodoroFocusDone` | Scheduled at focus start for its end | The Mac's | Start Break, Skip Break | `timeSensitive` |
| `pomodoroBreakDone` | Scheduled at break start for its end | The Mac's | Start Focus, End Pomodoro | `timeSensitive` |
| `longRunning` | N hours after the chain start, whichever device started it | "Still tracking Plan the widget layout?" / "Running for 4 hours." | Keep Running, Stop | `active` |
| `syncAdjusted` | Section 7, item 3, while the app is in the background | "An entry was changed" / the explanation | None; a tap opens the entry | `passive` |

Actions run in the background. Keep Running schedules the next `longRunning` N hours from now; Stop stops that entry only, not one started since. The reminder follows every change of the running entry and is removed when nothing runs.

## 9. Activity collection

Collection is opt-in per device. Collectors record raw, labeled events, never map them to projects, and apply exclusions before writing; the Mac agent merges them into blocks ([spec_activity_tracking.md](spec_activity_tracking.md) §6.2).

### 9.1 The collection file

Every collector appends one JSON line to `Activity/events.jsonl` in the App Group ([spec_data_and_sync.md](spec_data_and_sync.md) §6), with appends serialized across processes. A flush uploads the lines as `DeviceEvent` records and then removes those up to the acknowledged `lastFlushedSeq`, so an event appended meanwhile stays and an interrupted flush resumes without duplicates. Times are the device clock with the zone offset.

| Source | Label | Kind | Payload |
|---|---|---|---|
| `ladder` | The app set's label | `minute` | `{"n": 37}`, the step reached today; `"early": true` for a rejected callback |
| `focus` | The Focus filter's label | `on`, `off` | `{"collect": false}` on an `on` that suspends collectors |
| `intent` | The automation's label | the `ActivityEventKind` raw value | none |
| `webext` | The reduced URL (9.5) | `tab` | none |
| `app` | "TimeTracking" | `foreground`, `background` | none |

### 9.2 DeviceActivity ladder

The app requests Family Controls authorization from the Activity collection screen, never at launch. The monitor extension only appends (its memory ceiling is about 6 MB). With Screen Time denied, every other collector still works.

Each app set has a free-text label (suggested "Mail", "Messages", "Social", "Browsing", "Reading", "Work apps") and an opaque selection; only the label reaches the log. "Everything" measures all use of the device, is created automatically, and cannot be changed or deleted.

For each set, one repeating schedule runs from real midnight to real midnight, whatever the Midnight setting, with threshold events; the callback for step k appends a `ladder` line with `n = k`. "Everything" climbs in 1-minute steps to 60, a named set to 10, then both in 5-minute steps, never past a whole day. The day's first registration uses absolute thresholds with past activity; later ones use the minutes remaining after the last counted step.

The event cap is undocumented, so the first run measures it by registering 1, 2, 4, …, 512 events and keeping the largest count accepted. Named sets together get 16% of the cap (at least 10 each, at most half the cap) and "Everything" the rest: with a cap of 100 and one named set, "Everything" reaches 180 minutes and the named set 40. A set registers one window of its budget's size at a time; at the window's last step the extension registers the next.

A callback counts only if it comes no earlier than the last counted step's time plus the minutes between the two steps (the day's start for the first step). An earlier one is logged with `"early": true`, not counted, and re-registered with its remaining duration.

### 9.3 Focus filter

The filter has the parameters `label` ("Name") and `collect` ("Record Safari Sites and Automations", default true; false suspends the Safari and automation collectors while that Focus is on). It appends `on` when performed with a label and `off`, for the label last logged, when the system performs it with default parameters at the Focus's end; an `on` for another label first ends the current one. The system does not say which Focuses exist, so its suggestions are fixed: Work, Personal, Sleep, Fitness, Reading, Driving.

### 9.4 Automations

The user attaches `LogActivityEventIntent` to Shortcuts personal automations, which the app cannot create. iOS posts a notification for every immediate run, so the setup steps recommend it only for the two or three apps whose exact times matter, the charger, and arriving or leaving.

### 9.5 Safari web extension

The background script forwards http and https URLs of the active tab on activation and on a completed load or URL change. The native handler reads the exclusions from the App Group copy of `Activity/settings.toml`, refreshed at each foreground: a domain in `exclude_domains` is dropped, one in `private_domains` becomes the bare domain, and any other keeps domain plus path. Query strings, fragments, and titles are never stored. The user grants "All websites", so the exclusions are the privacy boundary.

### 9.6 Flush

Only the app flushes: at every foreground and every 5 minutes in the foreground, on every CloudKit push, in every refresh task, and on "Send Now". Every fan-out (so every wrapper intent) and every move to the background flushes only when the last flush is more than 5 minutes old.

### 9.7 The app's own time

The app appends `app` lines for its own foreground and background transitions.

## 10. The iPad

The iPad presents the sections with their behavior unchanged; this section states only the differences.

### 10.1 Tabs

Tabs (collapsible to a sidebar) in the order of the Mac's sidebar: Timer, Calendar, Reports, Projects, Activity. Timer is the iPhone screen, with the picker as a popover and, above 900 points, the card and the list side by side. Section adaptations are in [spec_projects.md](spec_projects.md) §1.4 and [spec_activity.md](spec_activity.md) §5. Toolbars map onto the navigation bar with the Mac's items and order ([spec_design.md](spec_design.md) §4), inspectors onto a trailing column, and dialogs onto sheets.

### 10.2 Touch and Pencil

| Mac interaction | iPad |
|---|---|
| Drag in an empty slot to draw an entry or block | Long press, then drag; Apple Pencil draws directly |
| Drag to move, drag an edge to resize, drag a block or event into Tracked | Long press lifts the item, then drag; Apple Pencil drags directly; the selected item shows 44-point resize handles |
| Hover tooltip or hover button | Tap shows a popover; Apple Pencil hover and a trackpad pointer act as hover |
| Right-click context menu | Long press |
| Zoom and sideways scrolling | Pinch vertically for the hours, horizontally for the day width. A sideways swipe with one or two fingers scrolls through time and coasts; a swipe starting mostly up or down scrolls the hours; a press held still lifts an item. Two fingers swiping sideways always change their spread a little, so a pinch zooms only once the spread changed by about 12%, and whichever starts first owns the touch until the fingers lift |
| Menu bar item, global shortcuts, login item, idle detection, reminders, CLI | Absent |

Only the iPad's Calendar tab requests calendar access; the iPhone never uses EventKit.

### 10.3 Hardware keyboard

The iPadOS menu bar has the Mac's menus, items, titles, and keys ([spec_timer.md](spec_timer.md) §9). The tabs are the Mac's sidebar items: an item of the Timer is enabled only in the Timer tab, an item of a section only in its tab, and a disabled item holds no key equivalent. It differs only where the iPad has no counterpart:

| Mac | iPad |
|---|---|
| Window › Mini Timer (⌥⌘R) | None; View › Timer (⌘1) selects the Timer tab with the task field focused |
| Continue (⌘O) continues the Timer's selected row | In the Timer tab, continues the most recent other entry; in a section tab, as on the Mac |
| Delete Entry… (⌘⌫) needs the list's focus | Needs a selected row |
| View › Mini Timer's Compact Mode and Float on Top; View › Activity's Exclude from Tracking… and Back | None |
| Edit › Copy (⌘C) copies the selected project names | Project › Copy Name only |

Esc closes a sheet or popover and clears a search.

### 10.4 Activity on the iPad

The iPad reads the block log and `LiveState`; it never writes the block log or runs the tracker. It runs the collection of section 9 for itself, opt-in.

## 11. Onboarding

1. Account. Without an available iCloud account, a full-screen "iCloud Needed" view with "Open Settings" and "Try Again" blocks everything else; the app needs the Mac's iCloud account with iCloud Drive on. Then "Name This Device" asks for the device name, prefilled with the system name, for the `Device` record.
2. Initial sync. "Receiving Your Data" shows progress and the entry count while the library fetches the zone. The iPad's tabs appear after this step.
3. Nothing else is asked at launch. Notification permission comes at the first start, Screen Time authorization from the Activity collection screen, calendar access when the iPad's Calendar tab first opens. The collection screen's setup steps for the Focus filter, automations, and Safari extension get a check mark once the app receives something from them.

## 12. Testable behaviors

- IOS-1. Start with an empty field and no project creates a running entry with empty task and no project; starting while another runs stops the first at the second's start (2.2).
- IOS-2. Return in the task field starts an entry while nothing runs and commits the task while one runs.
- IOS-3. Typing `@hou` opens the picker with search "hou"; choosing "Household" assigns it and removes "@hou" from the task.
- IOS-4. Create Project from the picker with a new client and area creates all three and assigns the project to the running entry (2.4).
- IOS-5. Continue on a row with an archived project shows the restore alert; Cancel starts nothing.
- IOS-6. A full leading swipe on a row continues it.
- IOS-7. The card's elapsed time and the Now widget count from the chain start: with Midnight at 00:00, at 00:30 an entry started at 23:00 shows 1:30:00 before and after the split, and the Today total includes 0:30:00 of it.
- IOS-8. Saving 23:00 to 01:00 in the edit sheet produces two entries split at midnight; an end later than now or before the start is refused; an overlap shows the notice with Keep and Revert (2.7).
- IOS-9. Starting a Pomodoro schedules `pomodoroFocusDone` for `focusEnd`; continuing another entry leaves the phase and `focusEnd` unchanged; stopping so that nothing runs, on any device, sets `off` and removes pending notifications.
- IOS-10. After termination and relaunch the Pomodoro state and notification are intact; a relaunch after `focusEnd` shows `focusOver` with "Start Break"; the replay never changes an entry.
- IOS-11. The Now widget's Stop stops the entry without opening the app, and the widget shows the idle state after its reload.
- IOS-12. A widget timeline has one entry with `.after(start of the next shown day)` without a local Pomodoro and `.after(phase end)` with one.
- IOS-13. The circular and rectangular Lock Screen widgets stop the running entry and otherwise continue the latest; every family shows a live elapsed time.
- IOS-14. The Pinned widget shows `pinnedProjectIDs` by default and an explicit list when configured; the running project's button stops it.
- IOS-15. A new push token reaches the `Device` record by the app's next run at the latest; with no widget installed the token becomes nil.
- IOS-16. A provider shows a `LiveState` running entry the store does not hold yet and reloads the timer control.
- IOS-17. Providers reloading within 10 s of a fetch, or within 5 s of the app's own write, do not fetch.
- IOS-18. A widget Stop on an entry known only from `LiveState` fetches changes first and then stops it.
- IOS-19. The control shows On exactly while an entry runs, after local changes, applied syncs, and provider updates; on a locked device it asks for authentication before acting.
- IOS-20. Siri "Start a timer in TimeTracking" with the answer "Bugfixes" applies the inference rule; the same intent from a Shortcuts action without a project assigns none.
- IOS-21. "Start tracking Household in TimeTracking" starts Household; a name matching two projects asks which one.
- IOS-22. The app calls `updateAppShortcutParameters()` after creating, renaming, archiving, or restoring a project and after a sync that changed projects.
- IOS-23. The silent-push handler finishes within 25 s, runs the fan-out, and calls the completion handler exactly once.
- IOS-24. An offline change is visible at once, shows the sync pill, and syncs at the next connection, after which the pill disappears.
- IOS-25. When the invariant pass stops an entry this device started, the banner appears and the row is badged until its sheet opens; a midnight split shows no banner.
- IOS-26. The `longRunning` notification is scheduled at the chain start plus the configured hours, also for an entry started on the Mac; Keep Running reschedules N hours later; Stop stops the entry.
- IOS-27. Concurrent appends from two processes never interleave lines; `lastFlushedSeq` advances only after CloudKit acknowledges the batch; two overlapping flushes keep an event appended while both were uploading.
- IOS-28. A ladder callback earlier than its ledger time is logged with `"early": true`, not counted, and re-registered.
- IOS-29. Turning a configured Focus on and off appends `on` and `off` lines with its label while the app is not running.
- IOS-30. The Safari handler drops `exclude_domains`, reduces `private_domains` to the domain, and strips query strings and fragments.
- IOS-31. A wrapper intent flushes only when the last flush is more than 5 minutes old.
- IOS-32. With Screen Time authorization denied, every other collector works.
- IOS-33. The iPhone never shows a calendar permission prompt; the iPad requests access when the Calendar tab first opens.
- IOS-34. On the iPad, ⌘1 selects the Timer tab with the task field focused, ⌘2 to ⌘5 select the four section tabs, and ⌘T does nothing in the Timer and Projects tabs.
- IOS-35. Drawing in the iPad's Tracked column creates an entry and opens the editor; a drawing past now is refused.
- IOS-36. The iPad never writes to `Activity/blocks/`.
- IOS-37. First launch without an iCloud account shows the blocking screen and nothing else.
- IOS-38. Opening `timetracking://start?project=Household` shows the Timer with a running Household entry; on the iPad `timetracking://planner/reports` selects the Reports tab.
- IOS-39. The iPad's menu context follows the Mac's: in the Timer tab Set Project… and Find are enabled and the Project menu's items are not; in Projects the Project menu's commands are enabled, Find focuses the search field, Set Project… is disabled, ⌘O on a selected project starts a timer on it, and with an area row selected the Project menu acts on the area and ⌘O has no project; in Calendar the Calendar's Entry and View commands, Go to Today, the period commands, and Find (focusing its search field) are enabled; Reports and Activity enable the period commands, and Date Range… opens their date popover.
- IOS-40. With Sleep on in the synced settings, the iPhone asks for sleep access at the next foreground and imports the night; turning Workouts on asks for both kinds and imports the workout; a refresh task imports without asking; with both off nothing is asked.
- IOS-41. An import records the synced import status with the device name and the kinds read; a refresh 10 minutes later leaves it unchanged, turning Workouts on rewrites it with both kinds at once, and a refresh an hour later moves its time.
- IOS-42. Tapping the card's elapsed time, tapping the running row, and the running row's Edit open the running entry's sheet with its task and End "Running"; the running row's context menu also has Copy Task and Discard. Moving Start 15 minutes earlier and Done moves the card's elapsed time by 15 minutes and keeps the task on the card and in the row; a task typed on the card just before is the sheet's task and is kept; a task stored after the sheet loaded is kept when Done changes only Start and the project.
- IOS-43. In the iPad's Calendar a swipe up scrolls the hours, a sideways swipe on the day headers or over the hours scrolls the days (and not the hours), and a pinch zooms; a long press then drag draws instead (IOS-35).
- IOS-44. In every section tab of the iPad, in portrait and landscape, the sidebar opens and closes with its button and the tabs then still switch by tap.
- IOS-45. A widget's Stop and the long-running notification's Stop stop only the entry they showed or its midnight continuation, checked and stopped in one write; an entry started since keeps running.
- IOS-46. A widget provider resolving while another provider's CloudKit fetch is still under way fetches too; a fetch counts for the 10-second reuse only once it returned.
- IOS-47. The app's ladder configuration and the monitor extension's callbacks read and write a set's ledger while holding the App Group lock; the device ID is created under the same lock.
- IOS-48. With Midnight at 04:00, a widget's today at 02:00 holds the stopped parts of the day and a live timer from the running entry's own start, a chain counted once, and its timeline ends at 04:00.
- IOS-49. The iPhone's Settings show Midnight.
- IOS-50. With "Play a sound" off a phase's notification is silent; on, it has its bundled sound; `longRunning` and `syncAdjusted` use the default sound.
- IOS-51. Typing in the edit sheet's task field lists up to four earlier tasks; `@` opens no picker; a tap on a suggestion sets the sheet's task and project, Done stores them, and Cancel leaves the entry unchanged.
- IOS-52. Turning the timer control off on an entry known only from `LiveState` fetches changes first and then stops it, or fails with the iCloud message; an entry started here since the widgets' last state is the one it stops.
