# Spec: iPhone and iPad App

One iOS target runs on iPhone and iPad. On the iPhone it is the Timer in pocket form (start, stop, continue, pick a project and task, the recent list, a Pomodoro), plus Home Screen and Lock Screen widgets, a Control Center control, App Shortcuts, and Siri. On the iPad the same Timer is the first tab, followed by Projects, Calendar, Reports, and Activity tabs that present the Mac's Planner sections. The target also hosts the device-side activity collection of [spec_activity_tracking.md](spec_activity_tracking.md) §6.2. Everything syncs through the shared library ([spec_data_and_sync.md](spec_data_and_sync.md)).

This spec states only what differs on a touch device. The Timer behavior is that of [spec_timer_window.md](spec_timer_window.md), the picker and project dialog are those of [spec_planner_projects.md](spec_planner_projects.md), and the intents, entities, and URL scheme are those of [spec_automation.md](spec_automation.md).

Not included: an Apple Watch app, Live Activities, idle detection, and the Mac's "remind me to track time" reminders.

## 1. Processes

The target names are those of [spec_architecture.md](spec_architecture.md) §1.1.

| Process | Target | Runs | Owns |
|---|---|---|---|
| App | `TimeTrackingiOS` | When open; briefly in the background on a silent push, background refresh, notification action, or an intent that runs in the app process | All screens, the sync engine, notifications, the widget push token upload, the flush of the collection file |
| Widget extension | `TimeTrackingWidgets` | During timeline and control reloads and push token changes | Widgets, the widget push handler, Control Center controls |
| App Intents extension | `TimeTrackingIntents` | When the system performs one of its intents | The Focus filter and `LogActivityEventIntent` |
| DeviceActivity monitor | `TimeTrackingMonitor` | On Screen Time threshold callbacks | Appending ladder events |
| Safari web extension | `TimeTrackingWebExtension` | While Safari changes tabs | Appending browsing events |

All five share the App Group `group.<APP_ID>` and the iCloud container `iCloud.<APP_ID>`.

Entry writes go through the app process. Interactive widget and control buttons run thin wrapper intents (6.1) in the app process: they conform to `LiveActivityIntent` for that reason only (WidgetKit performs such button intents by launching the app in the background), so the sync engine sends the change at once. The widget extension never writes the store: it keeps its push token and the last fetched `LiveState` in the App Group (4). The App Intents extension and the two collectors never open the store; they append through `DeviceEventSink.append`.

## 2. iPhone: the Timer screen

### 2.1 Layout

A navigation bar with the large title "Timer" and a settings button (`gearshape`). Below it, one inset-grouped list: the running-entry card as the first section, the Mac activity line (2.3) and the sync pill as its footer, the Siri tip until dismissed, and the day-grouped recent list (2.6). The list is `searchable` with the search field in the navigation bar's drawer (revealed by pulling down; ⌘F on a hardware keyboard focuses it): its filter matches and sums as the Timer window's ⌘F filter ([spec_timer_window.md](spec_timer_window.md) §3). Stop and Discard are on the card, Continue on every row. The iPhone has no tab bar, no calendar view, and no manual mode.

### 2.2 The running-entry card

The card is the Timer window's running-entry bar ([spec_timer_window.md](spec_timer_window.md) §2) in pocket form, with the 44 pt circle buttons of `spec_design.md` §7, in three rows:

1. The borderless task field, full width (`.title2`, placeholder "What are you working on?").
2. The project chip, at the card's leading edge.
3. The Pomodoro button (2.8), the elapsed time (`.title2`, medium weight, monospaced digits), then at the trailing edge the borderless Discard button while running and the Start or Stop button.

The Pomodoro countdown thus sits next to the elapsed time.

| State | Time shown | Actions |
|---|---|---|
| Nothing running | `0:00:00`, green Start button | Start (button, or Return in the task field) starts an entry with the field's task and the chip's project |
| Running | Elapsed time `h:mm:ss` since the midnight chain's start, as the Timer window's label; red Stop button | Stop, and Discard with the Timer window's confirmation text; Stop keeps the task and project as the draft; Discard is undoable (shake or three-finger undo) until the next change |
| Running with a Pomodoro | The elapsed time as above; the countdown is on the Pomodoro button (2.8) | As above |

Starting while another entry runs, from any surface, stops the running entry at the new start (`start(projectID:task:at:)`). The task field's commit timing, autocompletion, and `@` trigger are those of [spec_timer_window.md](spec_timer_window.md) §2.2; the suggestions appear as a list above the keyboard.

### 2.3 The Mac's current activity

When the `LiveState` record carries an activity part with `agentRunning` true for a Mac ([spec_data_and_sync.md](spec_data_and_sync.md) §4.1), a secondary-color line under the card shows the device name, the primary item's context and subject (the subject alone when the context is a plain app name), and the presence ("active", "passive", "idle since 14:02", "locked since 14:02", "asleep since 14:02"). With several Macs, one line each, at most two, most recently updated first. Without such a part the line is absent. On the iPad, tapping it opens the Activity tab.

### 2.4 Project picker and quick creation

The picker of [spec_planner_projects.md](spec_planner_projects.md) appears as a sheet (medium detent, resizable to large) from the chip or the `@` trigger, with the search field focused and the first match highlighted (Return chooses it). Choosing a project assigns it to the running entry or the draft and closes the sheet. "Create Project" pushes the project dialog, and its "New Area…" the area form with a `ColorPicker`, inside the same sheet; on Create the project is assigned and the sheet closes.

### 2.5 Archived projects

Continuing an entry whose project is archived shows the Timer window's alert ("Restore Project and Continue", "Cancel"). A row whose project is archived shows the project name in the secondary color.

### 2.6 The recent list

Grouping, headers, day totals (today's live with the running entry), the 14-day paging, and the row content are those of [spec_timer_window.md](spec_timer_window.md) §3. Section headers use `.headline` in the primary color, without uppercasing. The running entry is the first row of Today, its live duration in the accent color, without a continue button or swipes; a tap opens its edit sheet. Each other row has a 32 pt continue button at the trailing edge.

| Gesture | Action |
|---|---|
| Tap row | Edit sheet (2.7) |
| Tap ▶, or full leading swipe | Continue (`continue(_:at:)`) |
| Trailing swipe | Delete after the Timer window's confirmation; undoable until the next change |
| Long press | Context menu: Continue, Edit, Copy Task, Delete |

### 2.7 Entry editing

A sheet with the task field (autocompletion, no `@` trigger), the project chip, Start and End as date-and-time pickers, the resulting duration, "Created on <device name>" from the `Device` record in the secondary color, and Continue and Delete buttons. Done saves, Cancel discards. For the running entry End reads "Running" and only Start, task, and project change.

The future, overlap, and midnight-chain rules and their messages are those of [spec_timer_window.md](spec_timer_window.md) §4.2 and §4.3, checked on Done. An interval that crosses midnight shows "Will be saved as 2 entries, split at midnight" under the duration before saving.

### 2.8 Pomodoro

States, transitions, and the Pomodoro button (its look, countdown, ring, menu, and confirmation) are those of [spec_timer_window.md](spec_timer_window.md) §5, with the synced `pomodoro.focusMinutes` and `pomodoro.breakMinutes` and the device setting `pomodoro.sounds`; a tap acts as the Mac's click and a long press opens the menu where the Mac presses and holds. The card's time keeps the elapsed time. The Pomodoro is device-local: one started on the Mac is invisible on the phone, and the reverse. As on the Mac, Start Pomodoro is disabled while nothing runs. A pending confirmation turns the Pomodoro button into "Start Break" or "Start Focus".

What iOS adds:

1. The state (`phase`, `focusEnd`, `breakEnd`) is persisted in the device settings at every transition, and the phase's notification (8) is scheduled when the phase starts.
2. Whenever the app's process runs, it replays the persisted state: a passed phase end becomes the over-state, and if nothing runs the Pomodoro becomes `off` and its pending notifications are removed. The replay never changes an entry.
3. Sounds play at phase ends in the foreground; in the background the notification carries them.

### 2.9 Settings

A sheet from the toolbar: an inset-grouped `Form` with the inline title "Settings" and Done. The first screen holds short sections; longer settings are rows that push a screen of their own, with their current value trailing ("Pinned projects  3", "Activity collection  Off"). Explanations are section footers. Numbers are a row with the label, the value trailing, and a stepper ("Focus  25 min  − +").

| Section | Setting | Default | Scope |
|---|---|---|---|
| iCloud | Status, "Waiting to sync" (the outbox count), "Device name" (`Device.name`, a trailing text field), "Sync Now" | | Device |
| Pomodoro | Focus (1 to 180 min), Break (1 to 60 min) | 25, 5 | Synced |
| Pomodoro | Play a sound when a focus or break ends (`pomodoro.sounds`) | On | Device |
| Notifications | "Remind me when an entry runs long", "Remind after" N hours (1 to 12); while notifications are denied, the footer reads "Notifications are off, so focus, break, and reminder alerts won't appear." with "Open Settings" | On, 4 h (iPhone); off, 4 h (iPad) | Device |
| Widgets | "Pinned projects" pushes an ordered list over `pinnedProjectIDs`: add (`plus` in the navigation bar, the picker as a sheet), reorder and remove (Edit), an empty state with "Add Project" | Empty | Synced |
| Widgets | "Task for pinned buttons": "The project's last task" or "No task" | The project's last task | Device |
| Activity | "Activity collection" pushes the master switch; Screen Time authorization status and request; the "App Groups" section (9.2); setup steps for the Focus filter, automations, and the Safari extension with their check marks and a `ShortcutsLink`; an "iCloud" section with "Last sent", "Waiting to send", and "Send Now" | Off | Device |
| Activity | "Privacy" pushes a read-only view of the exclusions from `Activity/settings.toml` in three sections (websites, apps, files and terminals), with the note that they are edited in the Mac's Tracker pane | | Shared file |
| Calendars (iPad) | Which external calendars the Calendar tab shows, grouped by account | None | Device |
| About | Version and build ("1.0 (12)"), the app's Shortcuts link | | |

On screen an app set is an "app group" (`spec_design.md` §12). "Add App Group" offers the suggested names and "Custom…", which adds "New Group" and opens its screen. A group's screen has its label as the trailing text field "Name", the footer "Activity shows only this name, never the apps.", and the chosen apps, categories, and sites with "Choose Apps…", which presents the system's `familyActivityPicker`.

Collected activity goes to Activity (the Mac and iPad section), so the texts name that, never the log files: the Activity section's footer reads "Shows what you do on this device in Activity on your Mac and iPad.", and the master switch's "Records how long you use your app groups, when a Focus turns on or off, your automations, the Safari sites you visit, and when you use the app, so they appear in Activity. Nothing is added to your projects, and the Privacy exclusions are applied first." The setup footer reads "A step gets a check mark once the app receives something from it."; the Safari step ends "Sites listed under Privacy are left out." A failed send shows "Couldn't send your activity to iCloud. The app will try again." and a refused ladder "Screen Time couldn't start measuring these apps. Try again later."; the details go to the log.

## 3. Widgets

### 3.1 Common rules

Widgets read the store and the `LiveState` row (4) and act through the wrapper intents of 6.1. Each timeline is one entry at the current time with the policy `.after(date)`: the next Pomodoro phase end when a Pomodoro is active on this device, otherwise the next local midnight. Elapsed times are live timers (`Text(timerInterval:)`) from the running entry's chain start, which `LiveState` carries; the Today total counts the running entry from the later of its start and today's midnight.

Look (`spec_design.md` §6, §7 at widget scale): system text styles (task `.headline`, project line `.subheadline` with the 8 pt area dot and " · client" in `.secondary`, elapsed time `.title2.weight(.semibold)` with monospaced digits, totals and the Pomodoro `.caption` in `.secondary`); the start and stop circles of `CircleButtonStyle` (44 pt in Now, 32 pt in Recent rows, 24 pt as the Pinned stop mark) in system green and red; the background is `.background` through `containerBackground`, which the system removes in StandBy, on the Lock Screen, and in the tinted and clear Home Screen styles. In the accented and vibrant rendering modes the circles become one shape with the glyph cut out, marked `widgetAccentable()` with the area dot, the Pomodoro glyph, and the Lock Screen buttons. Live times use the system timer format (`m:ss` under an hour, `h:mm:ss` from one hour). A widget without content shows a centered symbol, title, and line ("No Pinned Projects", "No Recent Entries"). Task text is `privacySensitive()`. The gallery shows a running sample with recent rows and pinned projects.

Wherever a Pomodoro shows, the elapsed time stays the primary number and the countdown is a secondary line: the phase glyph (`pomodoro`, `cup.and.saucer`) in the accent color and the remaining time, or `+` and the time since the phase ended while its confirmation is pending (`spec_design.md` §11). Tapping outside a button opens the Timer (`timetracking://show`). Smart Stack relevance is 100 while an entry runs, 60 for one hour after one stops, 10 otherwise; the app donates the start and continue intents it performs. Buttons do nothing on a locked device. Before the first sync has delivered the store, every widget shows "Open <app name> to finish setting up", with the app's display name from the bundle (the name is personal, from `local.mk`).

### 3.2 Running entry widget ("Now")

| Family | Running | Idle |
|---|---|---|
| `systemSmall` | Area dot and project; task (two lines at most); the Pomodoro line when one is active on this device; elapsed time and the Stop circle bottom trailing | "Not tracking"; the most recent entry's task and project; "Today" total and the Continue circle |
| `systemMedium` | Task (one line with a Mac activity footer, else two); area dot, project, client; elapsed time; under it the "Today" total (live) and the Pomodoro line; Stop circle bottom trailing; footer with the Mac activity line of 2.3 | "Not tracking" and the "Today" total; the most recent entry with the Continue circle; Mac activity footer |

### 3.3 Recent entries widget ("Recent")

Families `systemMedium` (3 rows), `systemLarge` (7), and `systemExtraLarge` on the iPad (two columns of 7). While an entry runs, the first row is the running entry with its live time and Stop. The other rows are the most recent distinct (task, project) pairs (`recentCombinations(limit:)`) except the running pair, each with task, area dot, project, and a Continue button that starts that pair.

### 3.4 Pinned projects widget ("Pinned")

Configurable with `PinnedProjectsConfigurationIntent`: "Use pinned list" (default, the synced `pinnedProjectIDs`) or an explicit ordered list of 1 to 12 projects, and the task mode (default from Settings). Families `systemSmall` (2 buttons), `systemMedium` (4), `systemLarge` (8), `systemExtraLarge` (12). The buttons fill a fixed grid of the family's capacity (1, 2, 2, and 3 columns), so a family's buttons have one size however many are pinned. Each button is a rounded rectangle (12 pt corners, `.fill.secondary`) with the area dot and project and starts it (in "last task" mode with its most recent task); the running project's button takes a light tint of its area color, shows the 24 pt stop circle, and stops it. An archived project renders disabled with "Archived".

### 3.5 Lock Screen families

| Family | Running | Idle | Button |
|---|---|---|---|
| `accessoryInline` | `stopwatch` and "12:34 · Project", live | `stopwatch` and "Not tracking" | None; opens the app |
| `accessoryCircular` | Stop glyph above the live time ("12:34", hours from 60 minutes) | Play glyph | Stop, or Continue Latest |
| `accessoryRectangular` | Task, project, live time; `stop.circle.fill` trailing | "Not tracking", the most recent task; `play.circle.fill` trailing | Yes |

## 4. Live updates

The `LiveState` record, its fields, who writes it, and the Mac's `WidgetPushSender` are defined in [spec_data_and_sync.md](spec_data_and_sync.md) §4; credentials and transport in [spec_architecture.md](spec_architecture.md) §2.4. The iOS side:

1. Push token. Every widget configuration declares `.pushHandler(TimeTrackingWidgetPushHandler.self)`. The handler stores the token (hex), or nil when no widget is installed, in the App Group. The app records the stored token on this device's `Device` record through `setWidgetPushToken` (data spec §4.3) at launch, at every foreground, in the refresh task, and after every silent push, so a lost write repairs itself.
2. Reload. Every provider (Now, Recent, Pinned, and the control value providers) gets the running state from `LiveStateReader.fetch(timeout:)` (data spec §4.3) before building its entry. It reuses the last result, kept in the App Group, instead of fetching when the last fetch was less than 10 s ago (one push reloads several kinds) or the app wrote the running entry less than 5 s ago (a timestamp in the App Group). When the result changes the running entry, it reloads the timer control (`ControlCenter.shared.reloadControls(ofKind:)`). Client names, today's completed entries, recent pairs, and pinned projects come from the store; a project the store does not have yet shows without a client.
3. A widget button acting on an entry known only from `LiveState` runs its wrapper in the app process, which first fetches changes (at most 10 s) and then acts; if the entry still has not arrived, it fails with "Couldn't reach iCloud. Try again in a moment."
4. Without a running Mac app nothing sends widget pushes. Local changes reload widgets directly (section 7, item 4); changes from another iOS device arrive through the CloudKit silent push or the next refresh or foreground.

## 5. Control Center control and Action button

The `TimerToggle` control is a `ControlWidgetToggle` (display name "Timer") whose value provider uses the resolver of 4. Its label is the running task (else the project name, else "Tracking") when on and "Continue" when off, `privacySensitive()`. Its action, `ToggleTimerIntent`, runs in the app process: on continues the most recent entry, off stops the running entry. It requires authentication, so nothing starts or stops on a locked phone. The `controlWidgetActionHint`s are "Continue latest entry" and "Stop tracking". The app reloads the control after every change to the running entry, including synced ones.

The `StartProjectControl` is a `ControlWidgetButton` with a `ProjectEntity` parameter (`promptsForUserConfiguration()`) that starts that project through the start wrapper, for example on the Action button.

## 6. App Intents, App Shortcuts, Siri, and the URL scheme

### 6.1 Shared and iOS-only intents

The entities and shared intents come from the library's `AppIntentsPackage` ([spec_automation.md](spec_automation.md) §5). The `ProjectEntity` adopts `IndexedEntity` so projects appear in Spotlight.

| Intent | Runs in | Purpose |
|---|---|---|
| `WidgetStartIntent`, `WidgetStopIntent`, `WidgetContinueIntent` | App process | Widget and control buttons. Each calls the library operation, asks the sync engine to send at once, reloads timelines and controls, and flushes the collection file when the last flush is more than 5 minutes old. Hidden from Shortcuts. |
| `ToggleTimerIntent` | App process | Section 5 |
| `LogActivityEventIntent` | App Intents extension | `label: String` (shown as "Name"), `kind` (shown as "Type"; `appOpened`, `appClosed`, `arrived`, `left`, `chargerConnected`, `chargerDisconnected`, `custom`); appends an `intent` event (9.4) |
| `TimeTrackingFocusFilter` | App Intents extension | 9.3 |

Tracking intents performed before the first sync fail with "Open <app name> once to finish setting up." (the display name, as in 3.1).

### 6.2 App Shortcuts

The placeholder `${applicationName}` is "TimeTracking". The phrase table is defined once in the library and used by both apps. Every phrase also exists in a "with ${applicationName}" variant.

| Shortcut | Intent | Phrases | Icon |
|---|---|---|---|
| Start Timer | `StartTimerIntent` | "Start a timer in ${applicationName}", "Start tracking \(\.$project) in ${applicationName}", "Track \(\.$project) in ${applicationName}", "Start \(\.$project) in ${applicationName}" | `play.fill` |
| Stop Timer | `StopTimerIntent` | "Stop the timer in ${applicationName}", "Stop tracking in ${applicationName}", "Stop ${applicationName}" | `stop.fill` |
| Continue | `ContinueIntent` | "Continue in ${applicationName}", "Resume my last entry in ${applicationName}", "Continue \(\.$project) in ${applicationName}" | `arrow.counterclockwise` |
| What's Running | `CurrentEntryIntent` | "What am I tracking in ${applicationName}", "What's running in ${applicationName}", "Is ${applicationName} running" | `clock` |
| Today's Total | `TodayTotalIntent` | "How much have I tracked today in ${applicationName}", "${applicationName} total for today" | `sum` |
| Show Timer | `ShowTimerIntent` | "Open the timer in ${applicationName}" | `timer` |

The project token is an `AppShortcutPhraseToken` over `ProjectEntity`. The app calls `updateAppShortcutParameters()` after every change to the project list, local or synced. A `SiriTipView` for Start Timer appears once on the Timer screen until dismissed.

### 6.3 Siri

The Start Timer App Shortcut runs `StartTimerIntent` with its hidden `inferProject` parameter set (false by default, so Shortcuts actions never infer), which applies the inference rule of [spec_automation.md](spec_automation.md) §5; the dialog names the inferred project ("Started Bugfixes on Website."). When the phrase names no project, Siri asks "What are you working on?" and the answer becomes the task. A name matching two projects is disambiguated by the entity subtitle ("Website · Acme", "Website · Personal"). A name matching nothing fails with "I couldn't find a project called X." Today's Total for another day names it as spoken text ("2 hours on Thursday, March 14", with the year when it differs from this year).

### 6.4 URL scheme

The app handles the URLs of [spec_automation.md](spec_automation.md) §6 with `onOpenURL`. On the iPad, `planner/*` and `project/` URLs select the matching tab and its state.

## 7. Sync behavior

The library owns synchronization; this section states what the iOS app does around it.

1. Wake. The app declares the background modes for remote notifications and fetch. The silent-push handler passes the notification to the engine, waits at most 25 s, runs the fan-out of item 4, and calls the completion handler exactly once. The app also syncs at every foreground and in a `BGAppRefreshTask` rescheduled 15 minutes after each run.
2. Offline. Every change commits locally first; starting, stopping, continuing, and editing work offline from every surface. A sync pill under the card shows `waitingForNetwork`, `sending(n)` lasting over 10 s, or `error`, and disappears when the outbox is empty.
3. Adjustments. When the library emits `.adjusted` for an entry this device created or last edited, the Timer shows a banner "Another device changed an entry" with "Show", which opens that entry's edit sheet with a one-line explanation under the duration ("Stopped at 10:14 because an entry started on MacBook"). The row keeps a badge until its sheet has been opened once. A midnight split shows no banner.
4. Fan-out. After every applied sync and every local write, the app reloads the controls (and, after local writes, the widget timelines; the library reloads them after applied syncs), replays the Pomodoro, reschedules the long-running reminder, uploads a changed push token, updates the App Shortcut parameters when projects changed, flushes the collection file (9.6), and shows the banner of item 3 when applicable.
5. Midnight. The library's split runs whenever the app's process runs and at midnight while the app is in the foreground ([spec_data_and_sync.md](spec_data_and_sync.md) §1.5).

## 8. Notifications

Local notifications only. Authorization is requested at the first start of an entry on this device; if denied, the Pomodoro confirmation button still works and Settings shows a hint with a button to the system settings. The Pomodoro titles, bodies, and actions are those of [spec_timer_window.md](spec_timer_window.md) §10.

| Category | Trigger | Text | Actions | Level |
|---|---|---|---|---|
| `pomodoroFocusDone` | Scheduled at focus start for `focusEnd` | Timer window's | Start Break, Skip Break | `timeSensitive` |
| `pomodoroBreakDone` | Scheduled at break start for `breakEnd` | Timer window's | Start Focus, End Pomodoro | `timeSensitive` |
| `longRunning` | N hours (setting) after the running entry's chain start, whichever device started it | "Still tracking Plan the widget layout?" / "Running for 4 hours." | Keep Running, Stop | `active` |
| `syncAdjusted` | Section 7, item 3 applies while the app is in the background | "An entry was changed" / the explanation | None; tap opens the entry | `passive` |

Actions run in the background without opening the app: the Pomodoro actions perform their transitions; Keep Running schedules the next `longRunning` N hours from now; Stop stops the running entry. Tapping a body opens the Timer. The app reschedules `longRunning` whenever the running entry changes and removes it when nothing runs.

## 9. Activity collection

Collection is opt-in per device. Collectors record raw, labeled events, never map them to projects, and apply exclusions before writing; the Mac agent merges them into blocks ([spec_activity_tracking.md](spec_activity_tracking.md) §6.2).

### 9.1 The collection file

Every collector appends one JSON line through `DeviceEventSink.append(_:)` to `Activity/events.jsonl` in the App Group (location and `DeviceEvent` fields: [spec_data_and_sync.md](spec_data_and_sync.md) §6); the sink serializes appends across processes. The app's `flush()` turns the lines into `DeviceEvent` records and truncates the file; the record name and `lastFlushedSeq` make an interrupted flush resume without duplicates.

| Source | Label | Kind | Payload |
|---|---|---|---|
| `ladder` | The app set's label | `minute` | `{"n": 37}`, the step reached today; `"early": true` added for a rejected callback |
| `focus` | The Focus filter's label | `on`, `off` | none |
| `intent` | The automation's label | the `ActivityEventKind` raw value | none |
| `webext` | The reduced URL (9.5) | `tab` | none |
| `app` | "TimeTracking" | `foreground`, `background` | none |

Times are the device clock with the zone offset.

### 9.2 DeviceActivity ladder

The app and the monitor extension carry the Family Controls development entitlement. The app requests individual authorization from the Activity collection screen, never at launch. The monitor extension links only DeviceActivity, Foundation, and the sink, and only appends (its memory ceiling is about 6 MB).

App sets: each has a free-text label (suggested "Everything", "Mail", "Messages", "Social", "Browsing", "Reading", "Work apps") and an opaque `FamilyActivitySelection` from `FamilyActivityPicker`, shown with `Label(token)`. "Everything" uses `includesAllActivity`, is created automatically, and cannot be deleted. Only the label reaches the log, and the screen says so: "The app records daily minutes for each group. Activity shows only the group's name, never the apps in it." With Screen Time denied the footer reads "Screen Time access is off. Focus changes, automations, Safari sites, and your use of the app are still recorded."

For each set, one repeating `DeviceActivitySchedule` runs from midnight to midnight with `DeviceActivityEvent`s at thresholds of 1, 2, 3, … minutes and `includesPastActivity: true`; the callback for step k appends a `ladder` line with `n = k`. The first run measures the event cap by registering 1, 2, 4, …, 512 events and keeping the largest count `startMonitoring` accepts. The cap is divided among the sets by expected use (with a cap of 100: "Everything" 1-minute steps to 60 and 5-minute steps to 180; each named set 1-minute steps to 10, then 5-minute steps). At a set's last step the extension registers the next window of thresholds.

Early callbacks: a ledger per (set, step) holds the earliest possible time (the previous step's time plus 60 s). An earlier callback is logged with `"early": true`, not counted, and re-registered under a new name with its remaining duration.

### 9.3 Focus filter

The `TimeTrackingFocusFilter` is a `SetFocusFilterIntent` in the App Intents extension with parameters `label` ("Name", default the Focus name) and `collect` ("Record Safari Sites and Automations", default true; false suspends the Safari and automation collectors while that Focus is on). It appends `on` when performed and `off`, for the label it last logged, when the system performs it with default parameters at the Focus's end. The method `suggestedFocusFilters(for:)` offers one suggestion per Focus.

### 9.4 Automations

The user attaches `LogActivityEventIntent` to Shortcuts personal automations: "Is Opened" and "Is Closed" for the two or three apps whose exact times matter, charger connected or disconnected, and arrive or leave. Because iOS posts a notification for every immediate automation run, the setup instructions recommend it only for those few apps. The app cannot create automations; Settings offers a `ShortcutsLink` and a list of suggestions.

### 9.5 Safari web extension

The non-persistent background script listens to `tabs.onActivated` and `tabs.onUpdated` (status `complete` or a URL change) and sends `{url, time}` through `browser.runtime.sendNativeMessage`. The native handler reads the exclusions from the App Group copy of `Activity/settings.toml` (refreshed by the app from iCloud Drive at each foreground): a domain in `exclude_domains` is dropped, one in `private_domains` becomes the bare domain, otherwise domain plus path with the tracker's group-key rule for code hosts; query strings and fragments are always removed; titles are never stored. The user grants "All websites"; the exclusions are the privacy boundary. Private tabs are seen only if the user enables the extension there.

### 9.6 Flush

The app process alone calls `flush()`: at every foreground and every 5 minutes while open, on every CloudKit push, in every refresh task, from the wrapper intents when the last flush is over 5 minutes old, and on "Send Now" in Settings. The widget extension never flushes.

### 9.7 The app's own time

The app appends `app` lines for its own foreground and background transitions.

## 10. The iPad

The iPad presents the Planner sections with their behavior unchanged; this section states only the touch, Apple Pencil, and keyboard differences.

### 10.1 Tabs

A `TabView` with the iPadOS tab bar (collapsible to a sidebar): Timer, Projects, Calendar, Reports, Activity. Timer is the iPhone screen at iPad width, with the picker as a popover from the chip and the list in two columns above 900 points. The other tabs are [spec_planner_projects.md](spec_planner_projects.md) (§1.4 lists its iPad adaptations), [spec_planner_calendar.md](spec_planner_calendar.md), [spec_planner_reports.md](spec_planner_reports.md), and [spec_planner_activity.md](spec_planner_activity.md) (§5). Toolbars map onto the navigation bar with the items and order of the Mac ([spec_design.md](spec_design.md) §4): the period arrows and Today leading, the section's view options and actions trailing, the title inline, and items that do not fit in the system overflow menu. Inspectors map onto a trailing column and dialogs onto sheets.

### 10.2 Touch and Pencil

| Mac interaction | iPad |
|---|---|
| Drag in an empty slot of the Tracked or Calendar column to draw an entry or block | Long press, then drag; Apple Pencil draws directly. Snapping, the editor on release, and the refusal of future entries are the Calendar's. |
| Drag to move, drag an edge to resize | Long press lifts the item, then drag; the selected item shows 44-point resize handles at its top and bottom; Apple Pencil drags directly |
| Drag a block or event into the Tracked column | The same drag after a long press |
| Hover tooltip or hover button | Tap shows a popover with the text and actions; Apple Pencil hover and a trackpad pointer show it as hover does |
| Right-click context menu | Long press |
| Vertical and horizontal zoom | Pinch vertically and horizontally; two-finger swipe scrolls days |
| Print in Reports | The share sheet's Print |
| Menu bar item, global shortcuts, login item, idle detection, reminders, CLI | Absent |

The Calendar tab requests calendar access per [spec_planner_calendar.md](spec_planner_calendar.md); the iPhone never uses EventKit.

### 10.3 Hardware keyboard

The iPad uses the Mac's keys, listed in the iPadOS menu bar and the ⌘-hold overlay. In the Planner tabs every key is that tab's spec's.

| Keys | Action |
|---|---|
| ⌥⌘R | Timer tab, task field focused |
| ⌘1 to ⌘4 | Projects, Calendar, Reports, Activity |
| ⌥⌘P | Last Planner Tab: the most recently selected of those four (Projects at first) |
| ⌥⌘1 | Clients & Areas |
| ⌘N, ⌘O, ⌘S, ⌥⌘⌫ | New Entry, Continue Latest Entry, Stop, Discard Running Entry |
| ⌘P, ⌘E, ⌘⌫, ⌘F, ⌘↑ | Set Project, Edit Entry, Delete Entry, Find, Scroll to Top (the list's top; Timer tab only) |
| ⇧⌘P, ⌃⌘P, ⌘↩ | Start or Cancel Pomodoro, End Focus or Break Now, Start Break or Focus |
| ⌘Z, ⇧⌘Z, ⌘, | Undo, Redo, Settings |
| Esc | Close a sheet or popover, clear a search |

### 10.4 Activity on the iPad

The iPad reads the block log through `ActivityReading` and the Mac's activity from `LiveState`; it never writes the block log and never runs the tracker. It runs the collection of section 9 for itself, opt-in.

## 11. Onboarding

1. Account. The iCloud account status must be `.available`; otherwise a full-screen `ContentUnavailableView` ("iCloud Needed", `icloud.slash`; the app needs the Mac's iCloud account with iCloud Drive on) with the prominent "Open Settings" and "Try Again" blocks everything else. The device name is asked here, prefilled with the system name, and written to the `Device` record: a grouped form with the device symbol, the title "Name This Device", the line "Entries show where they were created.", the name field, and a full-width prominent "Continue" at the bottom (disabled while the name is empty).
2. Initial sync. The library fetches the zone before anything else shows: "Receiving Your Data" (`icloud.and.arrow.down`) with a progress indicator and the record count. The iPad's tab bar appears after this step.
3. Nothing else is asked at launch. Notification permission comes at the first start, Screen Time authorization from the Activity collection screen, calendar access when the iPad's Calendar tab first opens. The Activity collection screen has step-by-step instructions for the Safari extension, Focus filter, and automations, each checked off when the app detects it (extension messages received, Focus events received, authorization granted).

## 12. Testable behaviors

- IOS-1. Start with an empty field and no project creates a running entry with empty task and no project; starting while another runs stops the first at the second's start (2.2).
- IOS-2. Return in the task field starts an entry while nothing runs and commits the task while one runs.
- IOS-3. Typing `@hou` opens the picker with search "hou"; choosing "Household" assigns it and removes "@hou" from the task.
- IOS-4. Create Project from the picker with a new client and area creates all three and assigns the project to the running entry (2.4).
- IOS-5. Continue on a row with an archived project shows the restore alert; Cancel starts nothing.
- IOS-6. A full leading swipe on a row continues it.
- IOS-7. The card's elapsed time and the Now widget count from the chain start: at 00:30 an entry started at 23:00 shows 1:30:00 before and after the split, and the Today total includes 0:30:00 of it.
- IOS-8. Saving 23:00 to 01:00 in the edit sheet produces two entries split at midnight; an end later than now or before the start is refused; an overlap shows the notice with Keep and Revert (2.7).
- IOS-9. Starting a Pomodoro schedules `pomodoroFocusDone` for `focusEnd`; continuing another entry leaves the phase and `focusEnd` unchanged; stopping so that nothing runs, on any device, sets `off` and removes pending notifications.
- IOS-10. After termination and relaunch the Pomodoro state and notification are intact; a relaunch after `focusEnd` shows `focusOver` with "Start Break"; the replay never changes an entry.
- IOS-11. The Now widget's Stop stops the entry without opening the app, and the widget shows the idle state after its reload.
- IOS-12. A widget timeline has one entry with `.after(next midnight)` without a local Pomodoro and `.after(phase end)` with one.
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
- IOS-27. Concurrent appends from two processes never interleave lines; `lastFlushedSeq` advances only after CloudKit acknowledges the batch.
- IOS-28. A ladder callback earlier than its ledger time is logged with `"early": true`, not counted, and re-registered.
- IOS-29. Turning a configured Focus on and off appends `on` and `off` lines with its label while the app is not running.
- IOS-30. The Safari handler drops `exclude_domains`, reduces `private_domains` to the domain, and strips query strings and fragments.
- IOS-31. A wrapper intent flushes only when the last flush is more than 5 minutes old.
- IOS-32. With Screen Time authorization denied, every other collector works.
- IOS-33. The iPhone never shows a calendar permission prompt; the iPad requests access when the Calendar tab first opens.
- IOS-34. On the iPad, ⌥⌘R selects the Timer tab, ⌘1 to ⌘4 select the four Planner tabs, and ⌘T does nothing in the Timer and Projects tabs.
- IOS-35. Drawing in the iPad's Tracked column creates an entry and opens the editor; a drawing past now is refused.
- IOS-36. The iPad never writes to `Activity/blocks/`.
- IOS-37. First launch without an iCloud account shows the blocking screen and nothing else.
- IOS-38. Opening `timetracking://start?project=Household` shows the Timer with a running Household entry; on the iPad `timetracking://planner/reports` selects the Reports tab.

## 13. Decisions

- One target for iPhone and iPad; the iPhone gets only the Timer because the Planner views need the width.
- Widget and control buttons run in the app process, so the sync engine sends at once.
- Live updates use WidgetKit pushes from the Mac plus a direct fetch of `LiveState`, because CloudKit cannot send widget pushes and silent pushes are throttled.
- Control providers share the widgets' resolver, so the control follows a push without its own token.
- The Pomodoro replays only phase transitions, so replay order cannot change tracked time.
- Project inference is limited to the Siri App Shortcut; scripts and Shortcuts actions stay literal.
- The Control Center toggle continues the latest entry; the project control covers "always start X".
- The long-running reminder is off by default on the iPad so two devices do not remind at once.

## 14. Interfaces

- [spec_data_and_sync.md](spec_data_and_sync.md): `TimeStoreWriting` and `TimeStoreReading` (start, stop, continue, edit, delete, restore, create project, client, and area; running entry, `days(ending:count:)`, `overlaps(for:excluding:)`, `distinctTasks`, `recentCombinations(limit:)`); `StoreChange.adjusted`; `SyncStatus`; a fetch-now call on the sync engine; the midnight split and chain start; the `Device` record with `widgetPushToken` and `setWidgetPushToken`; `LiveState` and `LiveStateReader`; the settings `pomodoro.focusMinutes`, `pomodoro.breakMinutes`, `pomodoro.sounds`, `pinnedProjectIDs`, and the time-block calendar setting; `ActivityReading`; `DeviceEventSink` and `DeviceEvent`.
- Mac app (via the data spec's `WidgetPushSender`): a WidgetKit push to every iOS token whenever the running entry or a Mac's activity changes.
- [spec_architecture.md](spec_architecture.md): the five targets, entitlements, Info.plist keys, and development signing (sandbox APNs tokens).
- [spec_automation.md](spec_automation.md): entities, intents with their dialogs and errors, the Siri inference rule, and the URL scheme. This spec owns the phrase table and the wrapper intents, which call the library operations, not the intents' `perform()`.
- [spec_timer_window.md](spec_timer_window.md): the running-entry bar, task field, list, edit rules, Pomodoro state machine, notification texts, and keys.
- [spec_planner_projects.md](spec_planner_projects.md): the picker, project dialog, and area and client forms as shared views.
- Planner specs: the tab contents that section 10 adapts.
- [spec_activity_tracking.md](spec_activity_tracking.md): the merge of device events, the exclusion semantics, and Focus events as presence hints.
