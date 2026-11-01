# Spec: Timer and Main Window (Mac app)

The Timer is the Mac app's everyday surface: the running entry on top, recent entries by day below. It is the first item of the main window and, as the Mini Timer, a small window of its own. This spec also owns the main window, the main menu, the Pomodoro, idle detection, reminders, the settings window, the global shortcuts, and the shared entry editor.

## 1. Windows

The main window is one SwiftUI `Window` scene titled `<APP_NAME>`, opened at launch. Its sidebar is the iPad's adaptable tab view ([spec_ios.md](spec_ios.md) §10.1), shown on the Mac as a sidebar: Timer, Calendar, Reports, Projects, Activity, selected with View › Timer to Activity (⌘1 to ⌘5). The four sections are specified in [spec_projects.md](spec_projects.md) §1 and the section specs. Default size 1100 × 760 pt; the window is no smaller than the shown item's minimum. At launch it shows the Timer; clicking the Dock tile shows the window on its current item. Closing it keeps the app running.

The Timer item is laid out as the iPad's Timer tab: above 900 pt of width the running-entry bar (§2) is a column 40% of the width (400 to 480 pt) beside the list (§3), below it the bar sits above the list. It has no title-bar row and no pin; its minimum is 400 × 300 pt.

The Mini Timer is a second SwiftUI `Window` scene (`timer`, title "Mini Timer") with a hidden title bar, a small window for the bar and list like Music's MiniPlayer. The title-bar row holds only the traffic lights and, at the far right on their center line, the pin button (1.2); the rest of the row is empty and drags the window. Sections 1.1 to 1.3 are the Mini Timer's; the bar, list, and popover (§2 to §4) are the same in both places.

The two Timers are independent views of the same data. Each has its own selection, filter, and scroll position, its own task-field suggestions and `@` picker, project picker, edit popover, and project dialog, and its own keyboard focus: nothing opened, selected, or focused in one appears in the other, and the other shows the result once it is stored. Commands of the main menu act on the Timer of the key window. The Timer's alerts (Discard, Delete, Restore Project and Continue) appear in the key window, whatever it shows: Timer › Discard Running Entry with the main window on Calendar asks there. With no key window (the menu bar, a global shortcut, a notification), the Mini Timer comes forward with the alert. The idle prompt is the Mini Timer's (6.3).

### 1.1 Full and compact mode

| Quantity | Value |
|---|---|
| Bar height (compact window height) | 106 pt: the 32 pt title-bar row, the 32 pt control row, 8 pt, the chip, and a 14 pt bottom margin |
| Threshold | 200 pt: below it compact (bar only), at or above it full (bar and list) |
| Minimum full height | 300 pt |
| Minimum width (both modes) | 400 pt |
| Default full size | 480 × 600 pt |
| Default compact size | 480 × 106 pt |

The list hides and shows live as a resize crosses the threshold. A drag ending below the threshold animates to the bar height; one ending between the threshold and the minimum full height animates to the minimum full height, keeping the dragged width and the top-left corner.

Each mode's last frame is remembered (device settings `timerFullFrame`, `timerCompactFrame`). View › Compact Mode (⇧⌘M, checkmark, enabled while the Mini Timer is key) switches modes at the current top-left corner with the other mode's remembered size; a drag across the threshold applies the other mode's remembered height.

### 1.2 Pin

The pin button (`pin`, `pin.fill` while pinned) toggles window level `.floating`: above every app's normal windows, not joining other apps' full-screen spaces, without activating the window. It persists (device setting `timerPinned`, default off) and mirrors View › Float on Top. Settings has no separate checkbox for it.

### 1.3 Opening, closing, and restoration

The Mini Timer opens from Window › Mini Timer, the menu bar's "Show Mini Timer", and the show/hide shortcut (8.3); it never opens at launch. Opening it restores mode, frame, and pin; a frame with less than 100 × 44 pt on any screen moves to the main screen's center. The list starts at the top, the filter is cleared, and the task field is focused when nothing runs.

Launched as a login item, the app shows only the menu bar item unless "Show the main window at login" is on; otherwise it shows the main window. Closing a window keeps the app running. Quitting does not stop the running entry.

## 2. The running-entry bar

At the top of the Timer item, or below the Mini Timer's title-bar row, using the full width between the 20 pt insets, from left: the Pomodoro button (5.1, 32 pt circle while off, a fixed-width capsule while on); the borderless task field (placeholder "What are you working on?", `.title3`), which takes the remaining width; the timer label (`h:mm:ss` in `.title3`, medium weight, monospaced digits; `0:00:00` in the secondary color when idle); the start button (32 pt circle), which becomes the stop button while an entry runs; and the borderless discard button, only while running (`spec_design.md` §7).

Below that row, the project chip (`spec_design.md` §7: area dot, project, " · " and client in secondary color, `chevron.up.chevron.down`; "No project" with a hollow dot). The chip starts at the content inset, under the Pomodoro button and in line with the list rows, so it stays put in every Pomodoro state.

The timer label always shows the elapsed time, also during a Pomodoro, and counts from the running entry's chain start (the earliest start among the live entries sharing its `splitRootID` root, `spec_data_and_sync.md` 1.5), so it does not reset when the library splits the entry at midnight.

### 2.1 Start, stop, continue, discard

| Action | How | Effect |
|---|---|---|
| Start | Start button; Return in the task field while idle | Starts an entry with the field's task and the chip's project (both may be empty). |
| New | ⌘N | Starts an entry with empty task and no project; shows the Timer (the key window's; otherwise the Mini Timer while it is open, else the main window's Timer item) with the task field focused. |
| Stop | Stop button; ⌘S; continue/stop shortcut | Stops the running entry; the task field, project chip, and timer go blank as at startup. Resuming it is a Continue on its row, the first of the list. |
| Continue | Row's continue button; double-click; ⌘O; continue/stop shortcut while idle | Starts an entry with the source's task and project. ⌘O continues the selected row, else the most recent entry other than the running one. |
| Discard | Discard button; ⌥⌘⌫ | Deletes the running entry after the alert "Discard the running entry? 0:12:34 will be lost." (Discard, Cancel); ⌥-click skips the alert. Undoable with ⌘Z. |

Every start stops a running entry at the same instant. Continuing an entry of an archived project shows an alert with "Restore Project and Continue" and "Cancel".

### 2.2 The task field

While an entry runs, the field edits its task: a change commits 500 ms after the last keystroke and on Return, focus loss, or window close. Escape reverts to the stored task; Escape in an unchanged field moves focus to the list. While nothing runs, the field holds the draft, which is empty (placeholder "What are you working on?", no project) after a stop or a discard, on this or another device, until something is typed or picked.

Autocompletion: from the first character a popup lists up to 8 distinct (task, project) pairs whose task contains the text (case- and diacritic-insensitive), the chip's project first, then most recent. ↑ and ↓ move, Return or Tab accepts (sets task and project; Return also starts if idle), Escape closes.

The `@` trigger: an `@` at the start of the field or after a space opens the picker (2.3) while focus stays in the field; the text after it, spaces included, is the search, and ↑, ↓, and Return drive the picker. A choice assigns the project and removes the `@` text. Escape closes the picker leaving the text; deleting the `@` closes it. An `@` inside a word (`a@b`) does nothing.

### 2.3 Project chip, picker, and quick creation

Clicking the chip, Entry › Set Project… (⌘J), Space on the chip (Tab reaches it from the task field), or `@` opens the shared project picker (`spec_projects.md` §5) on the chip, with task matching on. Its search field takes focus except when opened by `@`. A choice sets the running entry's project at once, or the draft's.

The picker's "Create Project" row opens the project dialog (`spec_projects.md` §3) as a sheet; Create assigns the new project the same way.

## 3. The list

Entries are grouped by day. Headers read "Today", "Yesterday", then "EEE, MMM d" ("Tue, Oct 27"), with the year for other years, and show the day total `h:mm:ss` at the right. The running entry is the first row of its day, with its live duration in the accent color and no continue button; it is not selectable, and a click opens its edit popover (4). It counts toward today's total, which ticks every second; a filter it does not match hides its row and its seconds. Empty days are omitted. The list loads the 14 most recent days with entries; "Load Earlier Entries" (or scrolling to the end) appends 14 more. Each entry is its own row.

A row shows the task ("No task" in placeholder style), below it the project line (area dot, project, " · client" in secondary), and the duration at the right; every row has the same height. The continue button (24 pt circle) shows on hover and on the selected row, in space the row always reserves, so the duration never moves; the tooltip shows the range ("9:10 to 9:35"). Without entries the list shows "No Entries"; a filter without matches shows the system's search empty state.

| Input | Effect |
|---|---|
| Click | Select and open the edit popover (4) |
| Double-click | Continue |
| Context menu | Continue, Edit…, Delete… |
| ↑, ↓ | Move selection |
| Return | Edit popover |
| ⌘O | Continue selection |
| ⌘⌫ | Delete after the alert "Delete this entry? 0:25:00, Household" (Delete, Cancel); undoable with ⌘Z |
| Escape | Clear selection |
| ⌘↑ | Scroll to top (View › Scroll to Today) |

Filter: Edit › Find (⌘F) shows a field above the list; only entries whose task, project, client, or area contains the text (case- and diacritic-insensitive) remain, and day totals sum the shown entries. Escape clears and hides the field.

## 4. The edit popover

Clicking a row, Return on a selection, ⌘E, or clicking the timer label opens the edit popover; the Calendar reuses it. Fields, top to bottom, as rows with trailing-aligned labels: Task, Project (the chip), Start, Stop, Duration, Date; then the chain lines of 4.3 and the notices; then "Delete Entry…".

### 4.1 Fields

| Field | Input |
|---|---|
| Task | Text with the autocompletion of 2.2, no `@` trigger |
| Project | The chip; click or ⌘J opens the picker |
| Start, Stop | Time of day in the system's 12- or 24-hour format; `9:1` reads as 09:10; stored seconds are kept |
| Duration | `h:mm:ss`, also `25m`, `1h 30m`, `1:30` |
| Date | Date picker |
| Delete | Destructive button with the alert of 3 |

Each field commits on Return or focus loss. Escape in an edited field reverts it; Escape in an unchanged field, or a click outside, closes the popover. ⌘⌫ deletes.

### 4.2 Rules

Editing Start keeps Stop and recomputes Duration; editing Stop or Duration keeps Start and recomputes the other. A Stop at or before Start means the next date. Changing Date moves the entry by whole days, keeping its times.

A commit that would put any start or stop after now is refused: the field reverts and "Entries cannot be in the future" shows under the fields until the next edit.

A change that overlaps another entry (`overlaps(for:excluding:)`) shows the inline notice "Overlaps “Morning Review” (9:00 to 9:25)" with "Keep" (stores it) and "Revert".

For the running entry, Stop shows "running", Duration the live elapsed time of this entry (not the chain), and Stop, Duration, and Date are disabled.

### 4.3 Midnight chains

The library stores an interval across midnight as pieces sharing a root (`spec_data_and_sync.md` 1.5); these pieces form a midnight chain.

- A commit that makes the entry cross midnight is split by the library; the popover stays on the piece of its date (now ending at 00:00) and shows "Continues on Thu, Oct 29 until 00:35".
- For any piece of a chain, lines name the adjacent pieces: "Continued from Wed, Oct 28, 23:10" and "Continues on Thu, Oct 29 until 00:35".
- Task and Project changes apply to every live piece of the chain in one transaction; Start, Stop, Duration, Date, and Delete apply to the edited piece only.

The Timer creates entries only by starting them; past intervals are created in the Calendar.

## 5. Pomodoro

The Pomodoro lays focus and break phases over the running entry and notifies at phase ends. It never starts, stops, or splits entries. Its state is device-local, in memory; quitting ends it.

### 5.1 Controls and display

The Pomodoro button is the countdown's only place; the timer label keeps the elapsed time. Its look is that of `spec_design.md` §7:

| State | Shows | Click | Menu |
|---|---|---|---|
| Off, an entry runs | The apple (`pomodoro`, `spec_design.md` §5) in a 32 pt circle | Start Pomodoro | Press and hold: "Start Pomodoro (25 min)" (the focus duration) |
| Off, idle | The same | The menu | "Start Pomodoro (25 min)", disabled |
| Focus, break | A capsule: progress ring (accent color in focus, secondary on a break) and the countdown `m:ss` (`h:mm:ss` from one hour) | The menu | The phase and countdown ("Focus 24:59", "Break 4:30"), then the actions 5.3 allows and "Cancel Pomodoro" |
| Focus over, break over | The same capsule tinted with the accent color: `cup.and.saucer` and "Break", or `pomodoro` and "Focus"; tooltip "Start Break (⌘↩)" or "Start Focus (⌘↩)" | The confirmation; ⌘↩ anywhere in the Timer's window | Secondary click: the actions 5.3 allows and "Cancel Pomodoro" |

Every menu ends with "Pomodoro Settings…". The tooltip and the accessibility value name the phase and the countdown, in overtime as `+m:ss` counting up ("Focus +1:20").

### 5.2 Settings (Settings > Pomodoro)

| Setting | Key | Default | Range | Scope |
|---|---|---|---|---|
| Focus duration | `pomodoro.focusMinutes` | 25 min | 1 to 180 | synced |
| Break duration | `pomodoro.breakMinutes` | 5 min | 1 to 60 | synced |
| Play a sound when a focus or break ends | `pomodoro.sounds` | on | | device |

A duration change applies from the next phase. Phase-end notifications use two bundled sounds when sounds are on, else the default. Phase ends are absolute times (`focusEnd`, `breakEnd`), so a Mac that sleeps through one wakes into overtime and notifies at wake.

### 5.3 State machine

In the table, F and B are the focus and break durations.

| State | Event | Next | Effect |
|---|---|---|---|
| off | Start Pomodoro (an entry runs) | focus | `focusEnd = now + F` |
| focus | `now ≥ focusEnd` | focusOver | Notification "Focus done"; confirmation "Start Break" |
| focus | End Focus Now | break | `breakEnd = now + B` |
| focusOver | Start Break (button, menu, notification) | break | `breakEnd = now + B` |
| focusOver | Skip Break (menu, notification) | focus | `focusEnd = now + F` |
| break | `now ≥ breakEnd` | breakOver | Notification "Break over"; confirmation "Start Focus" |
| break | End Break Now | focus | `focusEnd = now + F` |
| breakOver | Start Focus (button, menu, notification) | focus | `focusEnd = now + F` |
| any but off | Cancel Pomodoro; End Pomodoro (notification) | off | |
| any but off | New or continued entry (any source or device); midnight split | unchanged | |
| any but off | Stop or discard leaving nothing running (any source or device, including idle Discard) | off | Pending notifications removed |
| any but off | App quits | off | |

Idle detection (6) runs unchanged in every phase.

## 6. Idle detection

### 6.1 Signal

Every 10 s the app reads the seconds since the last input event (`CGEventSource`, combined session state) and records the times of sleep, wake, power-off, session switch, and screen lock and unlock.

While the tracker is running (`spec_activity_tracking.md` §4.4), the app also reads `presence` from the local `current.json`: `passive` suppresses the prompt while it lasts, and `locked`, `asleep`, and `other_user` supply their exact `since`. The idle start is the earliest of now minus the idle seconds and the time of a lock, sleep, or user switch within the current absence.

### 6.2 Settings (Settings > Idle, device)

| Setting | Default |
|---|---|
| Detect idle time while an entry is running | on |
| Idle after (`idle.thresholdMinutes`) | 10 min (1 to 120) |
| On lock or sleep | "Ask when I return" (default), "Stop the entry at that moment", "Keep tracking" |
| Stop the running entry on shutdown or logout | on (stop time is the shutdown or logout) |

### 6.3 The prompt

When input resumes after an idle period of at least the threshold (or a lock or sleep with "Ask when I return") while an entry runs and presence was not `passive`, the Mini Timer comes forward with the sheet "You have been away": "Idle since 14:02 (23 minutes).", "Running: <task> · <project>", and the buttons Split, Discard and Continue, Discard, Keep. If the app is not frontmost, the `idle` notification is posted too. A new idle period extends an open prompt.

| Option | Effect | Key |
|---|---|---|
| Keep | Entry keeps running, idle time included | Return (default), Escape |
| Discard | Entry stops at the idle start | ⌘D |
| Discard and Continue | Entry stops at the idle start; an entry with the same task and project starts now | ⇧⌘D |
| Split | Entry stops at the idle start; a running entry with empty task and no project starts at the idle start; the task field is focused | ⌘S |

The prompt closes if the entry stops on another device. With "Stop the entry at that moment", a lock or sleep stops the entry at that time without a prompt. An entry stopped at shutdown needs no prompt at the next launch.

## 7. Reminders (Settings > Reminders, device)

| Setting | Default |
|---|---|
| Remind me to track time | off |
| Every | 10 min (1 to 240) |
| Between | 09:00 and 17:00 (end exclusive) |
| On | Monday to Friday |
| Snooze for | 60 min (5 to 480) |

While on, idle, inside the hours on a selected day, and unlocked, the app sends the `reminder` notification every N minutes, counted from the last stop or reminder. Snooze pauses reminders for the snooze duration.

## 8. Settings window

Settings… (⌘,) opens a SwiftUI `Settings` scene with six toolbar panes: General (`gearshape`), Pomodoro (`pomodoro`), Idle (`moon.zzz`), Reminders (`bell`), Shortcuts (`keyboard`), Tracker (`waveform.path.ecg`). It reopens on the last pane shown. Changes apply immediately.

Every pane is a grouped `Form` 520 pt wide (`spec_design.md` §8). The window takes each pane's height (the form's scrolling is off and its height fixed to its content), except the Tracker pane, which is 620 pt tall and scrolls. Related settings share a section; explanations are section footers, never rows. A number with a stepper is a row with the label leading and the value, then the stepper, trailing ("Focus duration   25 min ⇅"). A dependent setting is disabled, not indented, while the setting it depends on is off.

### 8.1 General

| Section | Setting | Default | Notes |
|---|---|---|---|
| (none) | Open at login | off | `SMAppService.mainApp`; the first-launch alert proposes it (8.2) and the Tracker pane's setup shows it (`spec_activity_tracking.md` §7.4) |
| (none) | Show the main window at login | off | Disabled while "Open at login" is off |
| Menu bar and Dock | Show timer, Show seconds, Show project, During a Pomodoro, show | on, off, off, Timer and countdown | `spec_menubar.md` §6 |
| Menu bar and Dock | Show Dock icon | on | `spec_menubar.md` §4 |
| iCloud | "Sync" ("Up to date", "Not signed in to iCloud. Entries stay on this Mac.", "Couldn't sync with iCloud. The app will try again.") and "Widget updates" ("Instant", "Last sent at 10:42", "Off (no push key)" without a push key, "Not working" with the detail in the log), followed by an info button (as in the Tracker pane, `spec_activity_tracking.md` §7.4) whose popover says that the Mac pushes each timer change to the widgets within seconds, that without the APNs key widgets change only when iOS reloads them, and how to create the key, with `make apns-key P8=…` as the snippet | | `spec_data_and_sync.md` §3.1, §4.3 |

Without notification authorization, a last section shows "Notifications are off for this app." with the warning symbol and a button to the app's Notifications settings. The Pomodoro, Idle, and Reminders panes hold the settings of 5.2, 6.2, and 7, with footers that say what the durations and thresholds do.

### 8.2 Tracker

The pane's contents are specified in `spec_activity_tracking.md` §7.4. The tracker is registered only from the pane's "Enable Tracker" button.

At the first launch on a Mac, a sheet on the main window asks "Set up activity tracking?" with the text "The tracker records which apps, sites, and terminal sessions you work in, so the Calendar can suggest entries. It needs a few permissions.", the buttons "Open Tracker Settings" (opens this pane) and "Later", and the checkbox "Open `<APP_NAME>` at login", on by default. Either button sets the device setting `trackerOnboardingPrompted`, so the sheet appears once per Mac, and, with the checkbox on, turns on "Open at login" (8.1). Under `-UITesting` the app never registers its real login item.

### 8.3 Shortcuts

The two recorders use the KeyboardShortcuts package (names `showHideTimer`, `continueStop`), stored as device settings and registered system-wide; a shortcut already in use is reported and not stored.

| Setting | Default | Behavior |
|---|---|---|
| Show/hide Mini Timer | ⌥⌘R | If the Mini Timer is not the key window of the active app, activate the app and show the Mini Timer with the task field focused; otherwise hide the app. |
| Continue/stop timer | unassigned | Stop the running entry, or continue the most recent entry when nothing runs. No window is shown. |
| Show the Mini Timer when an entry starts | off | After an entry starts from the global shortcut, the menu bar, a notification, an intent, or another device, show the Mini Timer with the task field focused. |
| Show the Mini Timer when an entry stops | off | The same after an entry stops from those sources. |

Window › Mini Timer and the menu bar's "Show Mini Timer" display the show/hide shortcut as key equivalent (none when unassigned); choosing either only shows the Mini Timer.

## 9. Menus and keyboard

This section owns the main menu as a whole, on the Mac and, with the differences of [spec_ios.md](spec_ios.md) §10.3, on the iPad; the section specs list their sections' commands. The menus are object menus, as in Music or Mail: every window has the same menus, File, Edit, View, Timer, Entry, Project, and Window, and Entry and Project act on what is selected in the view shown.

Every menu and item is always listed, and an item that applies to one view is disabled elsewhere rather than hidden. Such an item holds its key equivalent only while it is enabled, because AppKit sends a key equivalent to the first item that has it, even a disabled one; this lets one key serve several views (⌘⌫ deletes a Timer row and a project, Delete a Calendar selection) and keeps a disabled item from taking a key from a text field. A command that several views share is one item acting on the view shown: Find, Continue, Edit Entry…, Delete, Go to Today, Previous and Next Period, and Date Range…. Navigation keys that a view handles itself (arrows, Tab, Escape) are not menu items, as elsewhere on the Mac.

| Menu | Holds |
|---|---|
| App | Settings…, Hide, Quit (standard) |
| File | New Project…, New Area…, New Client… ([spec_projects.md](spec_projects.md) §2.5); Close (standard); Export… of Reports |
| Edit | Undo, Redo, the pasteboard commands (standard), Find |
| View | The sidebar's items, the sidebar toggle, the shown range's navigation, then each view's display options under its own header (Timer, Calendar, Report, Activity), then the Mini Timer's |
| Timer | The running entry and the Pomodoro, from any window (the menu bar item's menu has the same commands) |
| Entry | The selected entry in the view shown: the Timer's running entry or row, the Calendar's selection ([spec_calendar.md](spec_calendar.md) §6), or the Reports entry list's row |
| Project | The selected project, area, or client in Projects ([spec_projects.md](spec_projects.md) §2.5) |
| Window | Mini Timer, then the standard items and the main window |

"Timer view" is the scope of an item enabled while the Timer is shown, in the main window or the Mini Timer; "Mini Timer key" while the Mini Timer is the key window.

| Menu | Command | Shortcut | Scope |
|---|---|---|---|
| App | Settings… | ⌘, | App |
| App | Hide, Quit | ⌘H, ⌘Q | App |
| Edit | Undo, Redo | ⌘Z, ⇧⌘Z | Delete, discard, and popover edits |
| Edit | Find | ⌘F | Timer view; Projects and Reports ([spec_projects.md](spec_projects.md) §1.2) |
| View | Timer, Calendar, Reports, Projects, Activity | ⌘1 to ⌘5 | App; shows the main window on that item |
| View | Scroll to Today | ⌘↑ | Timer view |
| View | Compact Mode | ⇧⌘M | Mini Timer key |
| View | Float on Top | | Mini Timer key |
| Timer | New Entry | ⌘N | App |
| Timer | Continue | ⌘O | App: the selection of the view shown (a Timer row; a selected project, titled "Start Timer"; or the one selected Calendar or Reports entry), else the most recent other entry |
| Timer | Stop | ⌘S | App |
| Timer | Discard Running Entry | ⌥⌘⌫ | App |
| Timer | Start Pomodoro / Cancel Pomodoro | ⇧⌘P | App |
| Timer | The next step, titled by its action: End Focus Now, Start Break, End Break Now, or Start Focus (End Focus Now, disabled, while the Pomodoro is off) | ⌃⌘P | App |
| Entry | Edit Entry… | ⌘E; ↩ in the Calendar | Timer view (running entry from the bar, selected row from the list), the Calendar's selection, the Reports list's row |
| Entry | Set Project… | ⌘J | Timer view |
| Entry | The Calendar's entry commands | [spec_calendar.md](spec_calendar.md) §6 | Calendar |
| Entry | Delete Entry… | ⌘⌫; Delete in the Calendar | Timer view with a selected row in the focused list; the Calendar's selection |
| Window | Mini Timer | ⌥⌘R (displayed, 8.3) | App |
| Window | Close, Minimize | ⌘W, ⌘M | Standard |

The Window menu lists each window once, by its title: the Mini Timer scene contributes no item of its own besides Window › Mini Timer.

## 10. Notifications

The Mac app sends these through `UNUserNotificationCenter`, requesting authorization at the first start of an entry.

| Category | Title / body | Actions | Sound |
|---|---|---|---|
| `pomodoroFocusDone` | "Focus done" / "25 minutes on Clarify noise model. Time for a break." | Start Break, Skip Break | focus-end sound or default |
| `pomodoroBreakDone` | "Break over" / "Ready for the next focus?" | Start Focus, End Pomodoro | break-end sound or default |
| `idle` | "You have been away" / "Idle since 14:02 while tracking Clarify noise model." | Keep, Discard, Discard and Continue, Split | default |
| `reminder` | "Nothing is being tracked" / "Last entry stopped at 13:40." | Start New, Continue Latest, Snooze | default |

Clicking a notification shows the Mini Timer (with the idle prompt for `idle`). Pending Pomodoro and idle notifications are removed when their state resolves elsewhere. Without authorization, the confirmation button and the idle sheet still work.

## 11. Testable behaviors

- TW-1. Mini Timer height drags snap per §1.1: release at 199 pt gives 106 pt, at 200 pt gives 300 pt, 106 to 250 pt gives 300 pt, with width as dragged (at least 400 pt) and top-left fixed.
- TW-2. ⇧⌘M toggles between the remembered compact and full frames at the current top-left corner; without remembered frames, between 480 × 106 and 480 × 600 pt.
- TW-3. Opened after a relaunch, the Mini Timer has its mode, frame, and pin state from quit; with the pin on it stays above another app's key window.
- TW-4. ⌥⌘R shows the Mini Timer with the task field focused, or hides the app when the Mini Timer is key; Window › Mini Timer displays the recorded shortcut and none when cleared.
- TW-5. Launched as a login item with "Show the main window at login" off, the app shows no window; quitting leaves a running entry running.
- TW-6. Each action of §2.1 has its effect; ⌘N and Continue stop a running entry at the instant the new one starts; ⌘O without selection continues the most recent other entry.
- TW-7. A task edit of the running entry is stored within 500 ms of the last keystroke; Escape reverts it.
- TW-8. Typing three characters shows at most 8 suggestions, the current project's first; accepting sets task and project.
- TW-9. Typing `@noi` opens the picker searching "noi" with focus in the task field; Return assigns the highlighted project and removes "@noi"; Escape leaves "@noi"; `a@b` opens nothing.
- TW-10. The picker search "noise" lists the project under which "Clarify noise model" was tracked within 90 days.
- TW-11. A project created from the picker is assigned to the running entry, or to the draft.
- TW-12. Discard deletes the running entry after the alert and ⌘Z restores it; continuing an archived project's entry starts nothing unless "Restore Project and Continue" is chosen.
- TW-13. With an entry running since 23:10, at 00:05 the timer label reads `0:55:00`, and the list later shows its two pieces under their own days.
- TW-14. Today's total includes the running entry's elapsed time and rises one second per second; the running entry is Today's first row with its project, and a filter it does not match removes both.
- TW-15. Two identical consecutive entries appear as two rows; the list shows 14 days with entries and "Load Earlier Entries" appends 14.
- TW-16. The list inputs of §3 act as listed.
- TW-17. ⌘F with "noise" leaves only matching entries, and day totals sum them.
- TW-18. The popover recomputes and moves entries per §4.2.
- TW-19. A commit that would put the entry after now is refused with "Entries cannot be in the future"; for the running entry Stop, Duration, and Date are disabled.
- TW-20. Stop 00:35 on an entry starting 23:10 stores two pieces split at midnight and shows "Continues on <next day> until 00:35".
- TW-21. A task change on one piece of a chain changes every piece; a Start change changes only that piece.
- TW-22. An overlapping change shows the inline notice; "Keep" stores it, "Revert" restores the field.
- TW-23. A Pomodoro shows the countdown and a filling ring on the Pomodoro button, then `+0:00` counting up at `focusEnd` with "Focus done" sent and "Start Break" shown on the button; the timer label keeps the elapsed time throughout.
- TW-24. Through a focus, break, and focus cycle the store holds one running entry and no stopped entry.
- TW-25. Every transition of §5.3 holds, including that pending notifications are removed when the state turns off.
- TW-26. A focus duration change during focus does not move `focusEnd`; waking after `focusEnd` lands in `focusOver` and notifies at wake.
- TW-27. With a 10 min threshold, 10 min 5 s without input while an entry runs prompts at the next input with "Idle since" the time input stopped; no prompt while `passive`, when nothing runs, or below the threshold.
- TW-28. The prompt's options act as in §6.3.
- TW-29. Lock, sleep, and shutdown follow the settings of §6.2, using the lock or shutdown time.
- TW-30. With reminders every 10 min, 09:00 to 17:00, weekdays, a reminder arrives 10 min after a stop at 10:00 on a Tuesday, none at 17:05 or on a Saturday; Snooze suppresses them for its duration.
- TW-31. The continue/stop shortcut stops or continues; with "Show the Mini Timer when an entry starts" on, the Mini Timer then appears with the task field focused.
- TW-32. Each notification category offers exactly its listed actions; the settings window reopens on the last pane shown.
- TW-33. The first-launch alert of §8.2 appears once per Mac; "Open Tracker Settings" opens the Tracker pane, and the agent stays unregistered until "Enable Tracker".
- TW-34. The first-launch alert's "Open `<APP_NAME>` at login" checkbox is on by default; checked, either button turns on "Open at login", unchecked neither does; under `-UITesting` the real login item is never registered.
- TW-35. Every window has the menus File, Edit, View, Timer, Entry, Project, and Window; Window lists the main window and "Mini Timer" once each. With the Timer shown Entry › Set Project… is enabled and View › Go to Today and the Project menu's items are not. In the Calendar Entry › Fill Day… and View › Go to Today and Previous Period are enabled, Set Project… is not, and there is no Next Day, Next Entry, or Deselect item. In Projects Project › Edit Project… is enabled for a selected project and File › New Project… always; there is no Start Timer item outside the Timer menu. View › Compact Mode is enabled only while the Mini Timer is key.
- TW-36. The Mini Timer and the main window's Timer are independent: the project picker, an edit popover, the selection, the filter, and a task-field focus request in one leave the other unchanged; a project chosen in one is the project of both; New from the main menu focuses the key window's Timer; a store change reloads both lists. An alert of the Timer shows in the key window, also while the main window shows another item, and with no key window the Mini Timer comes forward with it.

## 12. Decisions

- One main window holds every view, as on the iPad, so the main menu is the same everywhere and needs no per-window menus; the Mini Timer keeps the small floating window of the former Timer window for people who want it.
- The Mini Timer's mode follows its height, so it restores with the frame.
- The Pomodoro never changes entries; idle detection handles real absence.
- The Pomodoro belongs to the person: replacing the entry keeps the phase; only "nothing runs" ends it.
- The timer label counts the chain, day totals count each day's piece.
- The Pomodoro countdown lives on its button, so the running entry's elapsed time is never hidden.
- Task and project edits propagate along a chain; time edits do not.
- Edits commit per field; there is no Save button.
- The Timer only starts entries; past intervals belong in the Calendar.

## 13. Interfaces

Assumed from `spec_data_and_sync.md`:

- Entities `Client`, `Area` (color), `Project`, `TimeEntry` (with `splitRootID`), observed through `StoreObserving`.
- Writes `start`, `stop`, `continue`, `update`, `delete`, `restore`, `restoreProject`, and `transaction` (chain-wide task and project changes).
- Reads `runningEntry`, `chainStart(of:)`, `days(ending:count:)`, `distinctTasks`, `lastStoppedEntry(excluding:)`, `overlaps(for:excluding:)`, and the tasks of a project since a date.
- Settings keys `pomodoro.focusMinutes`, `pomodoro.breakMinutes`, `idle.thresholdMinutes`, and device keys for the rest.
- `ActivityReading.currentState()` for presence and `lastTick`.

Assumed from `spec_projects.md`: the project picker and project dialog. From `spec_activity_tracking.md`: the Tracker pane and the tracker's liveness rule.

Provided:

- The entry editor (§4) for the Calendar.
- An observable timer display state for the menu bar: running entry summary, chain start, most recent other entry, today's last stopped entry, Pomodoro state and phase end.
- Commands New, Continue, Stop, the Pomodoro actions, show the Mini Timer (optionally focusing the task field), show the main window, and open Settings on a pane.
- The Pomodoro state machine (§5.3), which iOS implements with persisted state.
