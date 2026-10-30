# Spec: Timer Window (Mac app)

The Timer window is the Mac app's everyday surface: the running entry on top, recent entries by day below. This spec also owns the Pomodoro, idle detection, reminders, the settings window, the global shortcuts, and the shared entry editor.

## 1. Window

One SwiftUI `Window` scene (`timer`, title "Timer") with a hidden title bar: the traffic lights sit in the bar's first row, and the bar's background drags the window.

### 1.1 Full and compact mode

| Quantity | Value |
|---|---|
| Bar height (compact window height) | 88 pt |
| Threshold | 200 pt: below it compact (bar only), at or above it full (bar and list) |
| Minimum full height | 300 pt |
| Minimum width (both modes) | 360 pt |
| Default full size | 440 × 560 pt |
| Default compact size | 440 × 88 pt |

The list hides and shows live as a resize crosses the threshold. A drag ending below the threshold animates to the bar height; one ending between the threshold and the minimum full height animates to the minimum full height, keeping the dragged width and the top-left corner.

Each mode's last frame is remembered (device settings `timerFullFrame`, `timerCompactFrame`). View > Compact Mode (⇧⌘M, checkmark) switches modes at the current top-left corner with the other mode's remembered size; a drag across the threshold applies the other mode's remembered height.

### 1.2 Pin

The pin button (`pin`, `pin.fill` while pinned) toggles window level `.floating`: above every app's normal windows, not joining other apps' full-screen spaces, without activating the window. It persists (device setting `timerPinned`, default off) and mirrors View > Float on Top and the General pane's checkbox.

### 1.3 Opening, closing, and restoration

The window opens from Window > Timer Window, the menu bar, the show/hide shortcut (8.3), and the Dock tile. At launch it restores mode, frame, and pin; a frame with less than 100 × 44 pt on any screen moves to the main screen's center. The list starts at the top, the filter is cleared, and the task field is focused when nothing runs.

Launched as a login item, the app shows only the menu bar item unless "Show the Timer window at login" is on; otherwise it shows the window. Closing the window keeps the app running. Quitting does not stop the running entry.

## 2. The running-entry bar

Row 1, from left: traffic lights; task field (placeholder "What are you working on?"); timer label (`h:mm:ss`, monospaced digits, `0:00:00` when idle); start button (green circle, white play glyph), which becomes the stop button (red circle, white square) while an entry runs; discard button (`xmark.circle`), only while running. Start, stop, continue, and pause buttons share one style on every platform: a filled circle with a white glyph about 36% of its diameter; large ones carry a soft halo of their color.

Row 2, from left: project chip (area color dot, project, " · " and client in secondary color, chevron; "No project" with a hollow dot); Pomodoro button (5.1); spacer; pin button.

The timer label counts from the running entry's chain start (the earliest start among the live entries sharing its `splitRootID` root, `spec_data_and_sync.md` 1.5), so it does not reset when the library splits the entry at midnight.

### 2.1 Start, stop, continue, discard

| Action | How | Effect |
|---|---|---|
| Start | Start button; Return in the task field while idle | Starts an entry with the field's task and the chip's project (both may be empty). |
| New | ⌘N | Starts an entry with empty task and no project; shows the window with the task field focused. |
| Stop | Stop button; ⌘S; continue/stop shortcut | Stops the running entry; its task and project stay as the draft. |
| Continue | Row's continue button; double-click; ⌘O; continue/stop shortcut while idle | Starts an entry with the source's task and project. ⌘O continues the selected row, else the most recent entry other than the running one. |
| Discard | Discard button; ⌥⌘⌫ | Deletes the running entry after the alert "Discard the running entry? 0:12:34 will be lost." (Discard, Cancel); ⌥-click skips the alert. Undoable with ⌘Z. |

Every start stops a running entry at the same instant. Continuing an entry of an archived project shows an alert with "Restore Project and Continue" and "Cancel".

### 2.2 The task field

While an entry runs, the field edits its task: a change commits 500 ms after the last keystroke and on Return, focus loss, or window close. Escape reverts to the stored task; Escape in an unchanged field moves focus to the list. While nothing runs, the field holds the draft.

Autocompletion: from the first character a popup lists up to 8 distinct (task, project) pairs whose task contains the text (case- and diacritic-insensitive), the chip's project first, then most recent. ↑ and ↓ move, Return or Tab accepts (sets task and project; Return also starts if idle), Escape closes.

The `@` trigger: an `@` at the start of the field or after a space opens the picker (2.3) while focus stays in the field; the text after it, spaces included, is the search, and ↑, ↓, and Return drive the picker. A choice assigns the project and removes the `@` text. Escape closes the picker leaving the text; deleting the `@` closes it. An `@` inside a word (`a@b`) does nothing.

### 2.3 Project chip, picker, and quick creation

Clicking the chip, ⌘P, Space on the chip (Tab reaches it from the task field), or `@` opens the shared project picker (`spec_planner_projects.md` §5) on the chip, with task matching on. Its search field takes focus except when opened by `@`. A choice sets the running entry's project at once, or the draft's.

The picker's "Create Project" row opens the project dialog (`spec_planner_projects.md` §3) as a sheet; Create assigns the new project the same way.

## 3. The list

Entries are grouped by day. Headers read "Today", "Yesterday", then "EEE, MMM d" ("Tue, Oct 27"), with the year for other years, and show the day total `h:mm:ss` at the right. The running entry is not a row, but counts toward today's total, which ticks every second. Empty days are omitted. The list loads the 14 most recent days with entries; "Load Earlier Entries" (or scrolling to the end) appends 14 more. Each entry is its own row.

A row shows the task ("No task" in placeholder style), below it the chip's project line, and the duration at the right; hovering shows a continue button; the tooltip shows the range ("9:10 to 9:35").

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
| ⌘↑ | Scroll to top (View > Scroll to Today) |

Filter: Edit > Find (⌘F) shows a field above the list; only entries whose task, project, client, or area contains the text (case- and diacritic-insensitive) remain, and day totals sum the shown entries. Escape clears and hides the field.

## 4. The edit popover

Clicking a row, Return on a selection, ⌘E, or clicking the timer label opens the edit popover; the Planner's Calendar reuses it. Fields, top to bottom: Task, Project, Start and Stop, Duration, Date, the chain lines of 4.3, Delete.

### 4.1 Fields

| Field | Input |
|---|---|
| Task | Text with the autocompletion of 2.2, no `@` trigger |
| Project | The chip; click or ⌘P opens the picker |
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

The Timer window creates entries only by starting them; past intervals are created in the Calendar.

## 5. Pomodoro

The Pomodoro lays focus and break phases over the running entry and notifies at phase ends. It never starts, stops, or splits entries. Its state is device-local, in memory; quitting ends it.

### 5.1 Controls and display

The Pomodoro button (`timer`) is a menu button. Off, it reads "Pomodoro" and offers "Start Pomodoro (25 min)" (the focus duration; disabled while idle). On, it reads the phase and countdown ("Focus 24:59", "Break 4:30", "Focus +1:20") and offers the actions 5.3 allows and "Cancel Pomodoro". Both menus end with "Pomodoro Settings…".

While on, the timer label shows the countdown `m:ss` (`h:mm:ss` from one hour), in overtime `+m:ss` counting up (accent color after focus, secondary after a break); the elapsed time moves to its tooltip. A pending confirmation replaces the Pomodoro button with a prominent default button ("Start Break" or "Start Focus"), so ⌘↩ confirms anywhere in the window.

### 5.2 Settings (Settings > Pomodoro)

| Setting | Key | Default | Range | Scope |
|---|---|---|---|---|
| Focus duration | `pomodoro.focusMinutes` | 25 min | 1 to 180 | synced |
| Break duration | `pomodoro.breakMinutes` | 5 min | 1 to 60 | synced |
| Play sounds at phase ends | `pomodoro.sounds` | on | | device |

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

When input resumes after an idle period of at least the threshold (or a lock or sleep with "Ask when I return") while an entry runs and presence was not `passive`, the Timer window comes forward with the sheet "You have been away": "Idle since 14:02 (23 minutes).", "Running: <task> · <project>", and the buttons Split, Discard and Continue, Discard, Keep. If the app is not frontmost, the `idle` notification is posted too. A new idle period extends an open prompt.

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

Settings… (⌘,) opens a SwiftUI `Settings` scene with six toolbar panes: General (`gearshape`), Pomodoro (`timer`), Idle (`moon.zzz`), Reminders (`bell`), Shortcuts (`keyboard`), Tracker (`waveform.path.ecg`). It reopens on the last pane shown. Changes apply immediately.

Every pane is a grouped `Form` 520 pt wide (`spec_design.md` §8). The window takes each pane's height (the form's scrolling is off and its height fixed to its content), except the Tracker pane, which is 620 pt tall and scrolls. Related settings share a section; explanations are section footers, never rows. A number with a stepper is a row with the label leading and the value, then the stepper, trailing ("Focus duration   25 min ⇅"). A dependent setting is disabled, not indented, while the setting it depends on is off.

### 8.1 General

| Section | Setting | Default | Notes |
|---|---|---|---|
| (none) | Open at login | off | `SMAppService.mainApp`; the first-launch alert proposes it (8.2) and the Tracker pane's setup shows it (`spec_activity_tracking.md` §7.4) |
| (none) | Show the Timer window at login | off | Disabled while "Open at login" is off |
| Timer window | Float above other windows | off | Same state as the pin; the footer says so |
| Menu bar and Dock | Show timer, Show seconds, Show project | on, off, off | `spec_menubar.md` §6 |
| Menu bar and Dock | Show Dock icon | on | `spec_menubar.md` §4 |
| iCloud | Sync and widget push status | | `spec_data_and_sync.md` §3.1, §4.3 |

Without notification authorization, a last section shows "Notifications are off for this app." with the warning symbol and a button to the app's Notifications settings. The Pomodoro, Idle, and Reminders panes hold the settings of 5.2, 6.2, and 7, with footers that say what the durations and thresholds do.

### 8.2 Tracker

The pane's contents are specified in `spec_activity_tracking.md` §7.4. The tracker is registered only from the pane's "Enable Tracker" button.

At the first launch on a Mac, after the Timer window appears, an alert asks "Set up activity tracking?" with the text "The tracker records which apps, sites, and terminal sessions you work in, so the Calendar can suggest entries. It needs a few permissions.", the buttons "Open Tracker Settings" (opens this pane) and "Later", and the checkbox "Open `<APP_NAME>` at login", on by default. Either button sets the device setting `trackerOnboardingPrompted`, so the alert appears once per Mac, and, with the checkbox on, turns on "Open at login" (8.1). Under `-UITesting` the app never registers its real login item.

### 8.3 Shortcuts

The two recorders use the KeyboardShortcuts package (names `showHideTimer`, `continueStop`), stored as device settings and registered system-wide; a shortcut already in use is reported and not stored.

| Setting | Default | Behavior |
|---|---|---|
| Show/hide Timer window | ⌥⌘R | If the Timer window is not the key window of the active app, activate the app and show the window with the task field focused; otherwise hide the app. |
| Continue/stop timer | unassigned | Stop the running entry, or continue the most recent entry when nothing runs. The window is not shown. |
| Focus app when the timer starts | off | After an entry starts from the global shortcut, the menu bar, a notification, an intent, or another device, show the Timer window with the task field focused. |
| Focus app when the timer stops | off | The same after an entry stops from those sources. |

Window > Timer Window and the menu bar's "Show Timer Window" display the show/hide shortcut as key equivalent (none when unassigned); choosing either only shows the window.

## 9. Menus and keyboard

"Timer key" commands are enabled only while the Timer window is key; the Planner sections define their own commands on the same keys.

| Menu | Command | Shortcut | Scope |
|---|---|---|---|
| App | Settings… | ⌘, | App |
| App | Hide, Quit | ⌘H, ⌘Q | App |
| Edit | Undo, Redo | ⌘Z, ⇧⌘Z | Delete, discard, and popover edits |
| Edit | Find | ⌘F | Timer key |
| Timer | New | ⌘N | App |
| Timer | Continue | ⌘O | App (selection only while Timer key) |
| Timer | Stop | ⌘S | App |
| Timer | Discard Running Entry | ⌥⌘⌫ | App |
| Timer | Set Project… | ⌘P | Timer key |
| Timer | Edit Entry… | ⌘E | Timer key: running entry from the bar, selected row from the list |
| Timer | Delete Entry… | ⌘⌫ | Timer key, list focus |
| Timer | Start Pomodoro / Cancel Pomodoro | ⇧⌘P | App |
| Timer | Next Pomodoro Phase | ⌃⌘P | App: End Focus Now, Start Break, End Break Now, or Start Focus |
| View | Compact Mode | ⇧⌘M | Timer key |
| View | Float on Top | | Timer key |
| View | Scroll to Today | ⌘↑ | Timer key |
| Window | Timer Window | ⌥⌘R (displayed, 8.3) | App |
| Window | Planner | ⌥⌘P | App |
| Window | Close, Minimize | ⌘W, ⌘M | Standard |

## 10. Notifications

The Mac app sends these through `UNUserNotificationCenter`, requesting authorization at the first start of an entry.

| Category | Title / body | Actions | Sound |
|---|---|---|---|
| `pomodoroFocusDone` | "Focus done" / "25 minutes on Clarify noise model. Time for a break." | Start Break, Skip Break | focus-end sound or default |
| `pomodoroBreakDone` | "Break over" / "Ready for the next focus?" | Start Focus, End Pomodoro | break-end sound or default |
| `idle` | "You have been away" / "Idle since 14:02 while tracking Clarify noise model." | Keep, Discard, Discard and Continue, Split | default |
| `reminder` | "Nothing is being tracked" / "Last entry stopped at 13:40." | Start New, Continue Latest, Snooze | default |

Clicking a notification shows the Timer window (with the idle prompt for `idle`). Pending Pomodoro and idle notifications are removed when their state resolves elsewhere. Without authorization, the confirmation button and the idle sheet still work.

## 11. Testable behaviors

- TW-1. Height drags snap per §1.1: release at 199 pt gives 88 pt, at 200 pt gives 300 pt, 88 to 250 pt gives 300 pt, with width as dragged and top-left fixed.
- TW-2. ⇧⌘M toggles between the remembered compact and full frames at the current top-left corner.
- TW-3. After relaunch the window has its mode, frame, and pin state from quit; with the pin on it stays above another app's key window.
- TW-4. ⌥⌘R shows the window with the task field focused, or hides the app when the window is key; Window > Timer Window displays the recorded shortcut and none when cleared.
- TW-5. Launched as a login item with "Show the Timer window at login" off, the app shows no window; quitting leaves a running entry running.
- TW-6. Each action of §2.1 has its effect; ⌘N and Continue stop a running entry at the instant the new one starts; ⌘O without selection continues the most recent other entry.
- TW-7. A task edit of the running entry is stored within 500 ms of the last keystroke; Escape reverts it.
- TW-8. Typing three characters shows at most 8 suggestions, the current project's first; accepting sets task and project.
- TW-9. Typing `@noi` opens the picker searching "noi" with focus in the task field; Return assigns the highlighted project and removes "@noi"; Escape leaves "@noi"; `a@b` opens nothing.
- TW-10. The picker search "noise" lists the project under which "Clarify noise model" was tracked within 90 days.
- TW-11. A project created from the picker is assigned to the running entry, or to the draft.
- TW-12. Discard deletes the running entry after the alert and ⌘Z restores it; continuing an archived project's entry starts nothing unless "Restore Project and Continue" is chosen.
- TW-13. With an entry running since 23:10, at 00:05 the timer label reads `0:55:00`, and the list later shows its two pieces under their own days.
- TW-14. Today's total includes the running entry's elapsed time and rises one second per second.
- TW-15. Two identical consecutive entries appear as two rows; the list shows 14 days with entries and "Load Earlier Entries" appends 14.
- TW-16. The list inputs of §3 act as listed.
- TW-17. ⌘F with "noise" leaves only matching entries, and day totals sum them.
- TW-18. The popover recomputes and moves entries per §4.2.
- TW-19. A commit that would put the entry after now is refused with "Entries cannot be in the future"; for the running entry Stop, Duration, and Date are disabled.
- TW-20. Stop 00:35 on an entry starting 23:10 stores two pieces split at midnight and shows "Continues on <next day> until 00:35".
- TW-21. A task change on one piece of a chain changes every piece; a Start change changes only that piece.
- TW-22. An overlapping change shows the inline notice; "Keep" stores it, "Revert" restores the field.
- TW-23. A Pomodoro shows the countdown, then `+0:00` counting up at `focusEnd` with "Focus done" sent and "Start Break" shown; the tooltip keeps the elapsed time.
- TW-24. Through a focus, break, and focus cycle the store holds one running entry and no stopped entry.
- TW-25. Every transition of §5.3 holds, including that pending notifications are removed when the state turns off.
- TW-26. A focus duration change during focus does not move `focusEnd`; waking after `focusEnd` lands in `focusOver` and notifies at wake.
- TW-27. With a 10 min threshold, 10 min 5 s without input while an entry runs prompts at the next input with "Idle since" the time input stopped; no prompt while `passive`, when nothing runs, or below the threshold.
- TW-28. The prompt's options act as in §6.3.
- TW-29. Lock, sleep, and shutdown follow the settings of §6.2, using the lock or shutdown time.
- TW-30. With reminders every 10 min, 09:00 to 17:00, weekdays, a reminder arrives 10 min after a stop at 10:00 on a Tuesday, none at 17:05 or on a Saturday; Snooze suppresses them for its duration.
- TW-31. The continue/stop shortcut stops or continues; with "Focus app when the timer starts" on, the window then appears with the task field focused.
- TW-32. Each notification category offers exactly its listed actions; the settings window reopens on the last pane shown.
- TW-33. The first-launch alert of §8.2 appears once per Mac; "Open Tracker Settings" opens the Tracker pane, and the agent stays unregistered until "Enable Tracker".
- TW-34. The first-launch alert's "Open `<APP_NAME>` at login" checkbox is on by default; checked, either button turns on "Open at login", unchecked neither does; under `-UITesting` the real login item is never registered.

## 12. Decisions

- The mode follows the window height, so it restores with the frame.
- The Pomodoro never changes entries; idle detection handles real absence.
- The Pomodoro belongs to the person: replacing the entry keeps the phase; only "nothing runs" ends it.
- The timer label counts the chain, day totals count each day's piece.
- Task and project edits propagate along a chain; time edits do not.
- Edits commit per field; there is no Save button.
- The Timer window only starts entries; past intervals belong in the Calendar.

## 13. Interfaces

Assumed from `spec_data_and_sync.md`:

- Entities `Client`, `Area` (color), `Project`, `TimeEntry` (with `splitRootID`), observed through `StoreObserving`.
- Writes `start`, `stop`, `continue`, `update`, `delete`, `restore`, `restoreProject`, and `transaction` (chain-wide task and project changes).
- Reads `runningEntry`, `chainStart(of:)`, `days(ending:count:)`, `distinctTasks`, `lastStoppedEntry(excluding:)`, `overlaps(for:excluding:)`, and the tasks of a project since a date.
- Settings keys `pomodoro.focusMinutes`, `pomodoro.breakMinutes`, `idle.thresholdMinutes`, and device keys for the rest.
- `ActivityReading.currentState()` for presence and `lastTick`.

Assumed from `spec_planner_projects.md`: the project picker and project dialog. From `spec_activity_tracking.md`: the Tracker pane and the tracker's liveness rule.

Provided:

- The entry editor (§4) for the Planner Calendar.
- An observable timer display state for the menu bar: running entry summary, chain start, most recent other entry, today's last stopped entry, Pomodoro state and phase end.
- Commands New, Continue, Stop, the Pomodoro actions, show the Timer window (optionally focusing the task field), and open Settings on a pane.
- The Pomodoro state machine (§5.3), which iOS implements with persisted state.
