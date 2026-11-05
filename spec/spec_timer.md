# Spec: Timer and Main Window (Mac app)

The Timer is the Mac app's everyday surface: the running entry on top, recent entries by day below. It is the first item of the main window and, as the Mini Timer, a small window of its own. This spec also covers the main window, the main menu, the Pomodoro, idle detection, reminders, the settings window, the global shortcuts, and the shared entry editor.

## 1. Windows

The main window (`<APP_NAME>`, default 1100 × 760 pt) holds every view, as on the iPad, so the main menu is the same everywhere. Its sidebar is the iPad's adaptable tab view ([spec_ios.md](spec_ios.md) §10.1): the Timer, then the four sections ([spec_projects.md](spec_projects.md) §1). It opens on the Timer. Above 900 pt of width the Timer item puts the running-entry bar (§2) in a column 40% wide (400 to 480 pt) beside the list (§3), otherwise above it; its minimum is 400 × 300 pt.

The Mini Timer is a small second window for keeping the Timer beside other apps, like Music's MiniPlayer. Its title-bar row holds the traffic lights and the pin (1.2) and drags the window. Sections 1.1 to 1.3 are the Mini Timer's; the bar, list, and popover are the same in both places.

The two Timers are independent views of the same data: each has its own selection, filter, scroll position, popups, popovers, dialogs, and keyboard focus, and the other shows only the stored result. Main menu commands act on the key window's Timer. The Timer's alerts (Discard, Delete, Restore Project and Continue) appear in the key window, whatever it shows; with no key window, the Mini Timer comes forward with the alert.

### 1.1 Full and compact mode

Below a height of 200 pt the Mini Timer is compact (bar only), at or above it full (bar and list); the mode follows the height, so restoring the frame restores it. The compact height is 106 pt, the minimum full height 300 pt, the minimum width 400 pt, and the default sizes 480 × 600 and 480 × 106 pt.

The list hides and shows live during a resize. A drag ending below the threshold animates to 106 pt, one ending between the threshold and 300 pt to 300 pt, keeping the dragged width and the top-left corner. View › Compact Mode switches modes at the current top-left corner with the other mode's remembered size (device settings `timerFullFrame`, `timerCompactFrame`).

### 1.2 Pin

The pin (`pin`, `pin.fill` while pinned), mirrored by View › Float on Top, floats the window above every app's normal windows, without joining other apps' full-screen spaces or activating the window. It persists (device setting `timerPinned`, default off).

### 1.3 Opening, closing, and restoration

Opening the Mini Timer restores mode, frame, and pin; a frame with less than 100 × 44 pt on any screen moves to the main screen's center. The list starts at the top, the filter is cleared, and the task field is focused when nothing runs; closing the window only hides it, so its list resets then.

The state macOS saves never decides what shows, because saved state, also after a crash or a force quit, made SwiftUI skip the launch window. The app itself opens the launch's windows once the store is open (when it can't be opened, the main window with the message). A login-item launch reopens the main window and the Mini Timer as far as they were open when the app last quit; with neither, only the menu bar item shows. Any other launch shows the window "At launch, show" (8.1) names. The device setting `openWindows` tracks the two windows as they open and close, so it survives an unclean exit, and freezes when a quit starts, so the closes during termination don't count. Under `-UITesting`, `-LoginItemLaunch YES` launches as a login item.

The Dock tile, the menus, the show/hide shortcut, notifications, and URLs open their windows also with no window open. Closing a window keeps the app running; quitting does not stop the running entry.

## 2. The running-entry bar

From left: the Pomodoro button (5.1); the task field (placeholder "What are you working on?"); the timer label (`h:mm:ss`, `0:00:00` when idle); the start button, which becomes the stop button while an entry runs; and, only while running, the discard button. Below them is the project chip ("No project" with a hollow dot). Their look is in `spec_design.md` §7.

The timer label always shows the elapsed time, also during a Pomodoro, and counts from the running entry's chain start (`spec_data_and_sync.md` 1.5), so it does not reset at the split at real midnight. Day totals count each day's part instead (3).

### 2.1 Start, stop, continue, discard

| Action | How | Effect |
|---|---|---|
| Start | Start button; Return in the task field while idle | Starts an entry with the field's task and the chip's project (both may be empty) |
| New | ⌘N | Starts an empty entry and focuses the task field of the key window's Timer, otherwise the Mini Timer while it is open, else the main window's Timer |
| Stop | Stop button; ⌘S; continue/stop shortcut | Stops the running entry; the bar goes blank as at startup |
| Continue | Row's continue button; double-click; ⌘O; continue/stop shortcut while idle | Starts an entry with the source's task and project; ⌘O takes the selected row, else the most recent entry other than the running one |
| Discard | Discard button; ⌥⌘⌫ | Deletes the running entry after the alert "Discard the running entry? 0:12:34 will be lost." (Discard, Cancel); ⌥-click skips the alert; undoable with ⌘Z |

Every start stops a running entry at the same instant. Continuing an entry of an archived project shows an alert with "Restore Project and Continue" and "Cancel".

### 2.2 The task field

While an entry runs, the field edits its task: a change commits 500 ms after the last keystroke, on Return, on focus loss, and before New, Continue, or Start Timer replaces the running entry. Escape reverts to the stored task, or, unchanged, moves focus to the list. While nothing runs, the field holds the draft, which is empty after a stop or a discard, on this or another device, until something is typed or picked.

From the first character, a popup lists up to 8 distinct (task, project) pairs whose task contains the text (case- and diacritic-insensitive), the chip's project first, then most recent. ↑ and ↓ move, Return or Tab accepts (sets task and project; Return also starts if idle), Escape closes.

An `@` at the start of the field or after a space opens the picker (2.3) while focus stays in the field; the text after it, spaces included, is the search, and ↑, ↓, and Return drive the picker. A choice assigns the project and removes the `@` text. Escape closes the picker leaving the text; deleting the `@` closes it. An `@` inside a word (`a@b`) does nothing.

### 2.3 Project chip, picker, and quick creation

Clicking the chip, ⌘J, Space on the chip (Tab reaches it from the task field), or `@` opens the shared project picker (`spec_projects.md` §5) with task matching on. A choice sets the running entry's project at once, or the draft's. "Create Project" opens the project dialog (`spec_projects.md` §3) as a sheet; Create assigns the new project the same way.

## 3. The list

Entries are grouped by the days of the Midnight setting (`spec_data_and_sync.md` §8). An entry across Midnight has a row on each of its days with that part's times, and its editor opens the stored entry; pieces split at real midnight inside one shown day stay separate rows. Headers read "Today", "Yesterday", then "EEE, MMM d" ("Tue, Oct 27"), with the year for other years, and show the day total `h:mm:ss`. Each entry is its own row, and empty days are omitted. The list loads the 14 most recent days with entries; "Load Earlier Entries" appends 14 more.

The running entry is the first row of its day, with its live duration in the accent color and no continue button; it is not selectable, and a click opens its edit popover. It counts toward today's total, which ticks every second; a filter it does not match hides its row and its seconds.

A row shows the task ("No task" in placeholder style), the project line, and the duration, with the range ("9:10 to 9:35") as tooltip. The continue button shows on hover and on the selected row, in space the row always reserves, so the duration never moves. Without entries the list shows "No Entries"; a filter without matches shows the system's search empty state.

A click selects a row and opens the edit popover, a double-click continues it, and the context menu has Continue, Edit…, and Delete…. ↑ and ↓ move the selection, Return edits it, ⌘O continues it, and Escape clears it. ⌘⌫ deletes after the alert "Delete this entry? 0:25:00, Household" (Delete, Cancel), undoable with ⌘Z. ⌘↑ scrolls to the top.

⌘F shows a filter field above the list: only entries whose task, project, client, or area contains the text (case- and diacritic-insensitive) remain, and day totals sum them. Escape clears and hides the field.

## 4. The edit popover

Clicking a row, Return on a selection, ⌘E, or clicking the timer label opens the edit popover; the Calendar and Reports reuse it. On the running entry the bar's task field commits first, so the popover shows the task just typed. The fields show the entry at once, before its stored values reload: a field that loses focus immediately commits what it shows, and a task typed before the reload is kept.

### 4.1 Fields

Top to bottom: Task (with the autocompletion of 2.2, no `@` trigger); Project (the chip; click or ⌘J opens the picker); Start and Stop (time of day in the system's format; `9:1` reads as 09:10; stored seconds are kept); Duration (`h:mm:ss`, also `25m`, `1h 30m`, `1:30`, `90s`, or plain minutes); Date (the stored entry's real date); the lines of 4.3 and the notices; "Delete Entry…" (⌘⌫), with the alert "Delete this entry?".

Each field commits on Return or focus loss; there is no Save button, and a field left unchanged stores nothing. Escape in an edited field reverts it; Escape in an unchanged field, or a click outside, closes the popover.

### 4.2 Rules

Editing Start keeps Stop, and a Start at or after Stop reverts. Editing Stop or Duration keeps Start, and a Stop at or before Start means the next date. Changing Date moves the entry by whole days, keeping its times. A commit stores only the times it changed, so a time changed elsewhere since the editor opened stays.

A commit that would put any start or stop after now is refused: the field reverts and "Entries cannot be in the future" shows until the next edit. A change that overlaps an entry outside its own chain shows the notice "Overlaps “Morning Review” (9:00 to 9:25)" with "Keep" (stores it) and "Revert".

For the running entry, Stop shows "running", Duration shows the live time of this entry (not the chain), and Stop, Duration, and Date are disabled.

### 4.3 Chains at real midnight

The library stores an interval across real midnight as pieces sharing a root, which form a chain (`spec_data_and_sync.md` 1.5); the Midnight setting doesn't affect this.

A commit that makes the entry cross midnight is split; the popover stays on the piece of its date, now ending at 00:00. For any piece, lines name the adjacent pieces: "Continued from Wed, Oct 28, 23:10" and "Continues on Thu, Oct 29 until 00:35". Task and Project changes apply to every live piece in one transaction; Start, Stop, Duration, Date, and Delete apply to the edited piece only.

The Timer creates entries only by starting them; past intervals are created in the Calendar.

## 5. Pomodoro

The Pomodoro lays focus and break phases over the running entry and notifies at phase ends. It never starts, stops, or splits entries; idle detection handles real absence. On the Mac its state is in memory, so quitting ends it; iOS runs the same state machine with persisted state (`spec_ios.md` §2.8). The state is device-local on both.

### 5.1 Controls and display

The Pomodoro button is the countdown's only place, so the timer label keeps showing the elapsed time.

| State | Shows | Click | Menu |
|---|---|---|---|
| Off | The apple (`pomodoro`) in a circle | Start Pomodoro while an entry runs, else the menu | "Start Pomodoro (25 min)", disabled while idle; press and hold while an entry runs |
| Focus, break | A fixed-width capsule: progress ring (accent color in focus, secondary on a break) and the countdown `m:ss` (`h:mm:ss` from one hour) | The menu | The phase and countdown ("Focus 24:59"), then the actions 5.3 allows |
| Focus over, break over | The capsule in the accent color: `cup.and.saucer` and "Break", or `pomodoro` and "Focus"; tooltip "Start Break (⌘↩)" or "Start Focus (⌘↩)" | The confirmation; also ⌘↩ anywhere in the window | Secondary click: the actions 5.3 allows |

Every menu ends with "Pomodoro Settings…". The accessibility value names the phase and the countdown, in overtime as `+m:ss` ("Focus +1:20").

### 5.2 Settings (Settings > Pomodoro)

| Setting | Key | Default | Range | Scope |
|---|---|---|---|---|
| Focus duration | `pomodoro.focusMinutes` | 25 min | 1 to 180 | synced |
| Break duration | `pomodoro.breakMinutes` | 5 min | 1 to 60 | synced |
| Play a sound when a focus or break ends | `pomodoro.sounds` | on | | device |

A duration change applies from the next phase. Phase ends are absolute times (`focusEnd`, `breakEnd`), so a Mac that sleeps through one wakes into overtime and notifies at wake.

### 5.3 State machine

Entering focus or break sets its end to now plus its duration.

| State | Event | Next |
|---|---|---|
| off | Start Pomodoro (an entry runs) | focus |
| focus | `now ≥ focusEnd`: notification "Focus done", confirmation "Start Break" | focusOver |
| focus | End Focus Now | break |
| focusOver | Start Break (button, menu, notification) | break |
| focusOver | Skip Break (menu, notification) | focus |
| break | `now ≥ breakEnd`: notification "Break over", confirmation "Start Focus" | breakOver |
| break | End Break Now | focus |
| breakOver | Start Focus (button, menu, notification) | focus |
| any but off | Cancel Pomodoro; End Pomodoro (notification); the app quits; nothing runs any more | off |

The Pomodoro belongs to the person, not the entry. A new or continued entry from any source or device and the split at real midnight leave the phase unchanged; only "nothing runs", after a stop or discard from any source or device (including idle Discard), ends it, and removes pending notifications. Idle detection runs unchanged in every phase.

## 6. Idle detection

### 6.1 Signal

Every 10 s the app reads the seconds since the last input event, and it records sleep, wake, power-off, session switches, and screen lock and unlock. While the tracker is running (`spec_activity_tracking.md` §4.4), its `presence` adds to this: `passive` (a video, a call) suppresses the prompt while it lasts, and `locked`, `asleep`, and `other_user` supply their exact `since`. The idle start is the earliest of now minus the idle seconds and the time of a lock, sleep, or user switch within the current absence.

### 6.2 Settings (Settings > Idle, device)

| Setting | Default |
|---|---|
| Detect idle time while an entry is running | on |
| Idle after (`idle.thresholdMinutes`) | 10 min (1 to 120) |
| On lock or sleep | "Ask when I return"; also "Stop the entry at that moment", "Keep tracking" |
| Stop the running entry on shutdown or logout | on (stops at that time) |

### 6.3 The prompt

When input resumes after an idle period of at least the threshold (or a lock or sleep with "Ask when I return") while an entry runs and presence was not `passive`, the Mini Timer comes forward with the sheet "You have been away": "Idle since 14:02 (23 minutes).", "Running: <task> · <project>", and the options below. If the app is not frontmost, the `idle` notification is posted too. A new idle period extends an open prompt, and the prompt closes if the entry stops on another device. A split at real midnight is no change of the running entry: the prompt stays open and acts on the chain.

| Option | Effect | Key |
|---|---|---|
| Split | Entry stops at the idle start; a running entry with empty task and no project starts there; the task field is focused | ⌘S |
| Discard and Continue | Entry stops at the idle start; an entry with the same task and project starts now | ⇧⌘D |
| Discard | Entry stops at the idle start | ⌘D |
| Keep | Entry keeps running, idle time included | Return, Escape |

An idle start before a split at real midnight stops the chain there: the piece running at that moment ends at the idle start, and the pieces after it are removed. The new entry of Split is split at midnight like any other.

With "Stop the entry at that moment", a lock or sleep stops the entry at that time without a prompt. An entry stopped at shutdown needs no prompt at the next launch.

## 7. Reminders (Settings > Reminders, device)

"Remind me to track time" is off by default. While on, idle, unlocked, and inside the hours on a selected day, the app sends the `reminder` notification every N minutes, counted from the last stop or reminder. The defaults are every 10 min (1 to 240), between 09:00 and 17:00 (end exclusive), Monday to Friday, snooze for 60 min (5 to 480). The hours and days are clock times and don't follow the Midnight setting.

A start, on any device, removes a delivered reminder; its Start New and Continue Latest do nothing while an entry runs, so they never stop an entry started since.

## 8. Settings window

Settings… (⌘,) has seven toolbar panes: General, Pomodoro, Idle, Reminders, Calendar, Shortcuts, Tracker. It reopens on the last pane shown, and changes apply immediately. As the macOS HIG describes, the window has the size of the current pane: 520 pt wide and as tall as its content, up to 720 pt, beyond which it scrolls; it can't be resized. A dependent setting is disabled, not indented, while the setting it depends on is off (`spec_design.md` §8).

### 8.1 General

The pane holds "Open at login" (off; the first-launch sheet proposes it), "At launch, show" (Main window or Mini Timer; default Main window, 1.3), the synced Midnight setting (00:00 to 23:00, default 00:00; `spec_data_and_sync.md` §8), and the section "Menu bar and Dock" (`spec_menubar.md` §6).

The section "iCloud" shows the status lines "Sync" and "Widget updates" (`spec_data_and_sync.md` §3.1, §4.3). An info button on the latter explains the widget pushes and how to install the APNs key (`make apns-key P8=…`).

Without notification authorization, a last section shows "Notifications are off for this app." and a button to the app's Notifications settings. The Calendar pane holds the settings of [spec_calendar.md](spec_calendar.md) §6, the same as on the iPad.

### 8.2 Tracker

The pane is specified in `spec_activity_tracking.md` §7.4. The tracker is registered only from its "Enable Tracker" button.

At the first launch on a Mac, a sheet on the main window asks "Set up activity tracking?" with the text "The tracker records which apps, sites, and terminal sessions you work in, for Activity and the Calendar. It needs a few permissions.", the buttons "Open Tracker Settings" (opens this pane) and "Later", and the checkbox "Open `<APP_NAME>` at login", on by default. Either button sets the device setting `trackerOnboardingPrompted`, so the sheet appears once per Mac, and, with the checkbox on, turns on "Open at login". Under `-UITesting` the app never registers its real login item.

### 8.3 Shortcuts

The two global shortcuts are stored per device; a shortcut already in use is reported and not stored.

| Setting | Default | Behavior |
|---|---|---|
| Show or hide the Mini Timer | ⌥⌘R | Hides the app if the Mini Timer is the key window of the active app; otherwise activates the app and shows the Mini Timer with the task field focused |
| Continue or stop the timer | unassigned | Stops the running entry, or continues the most recent entry when nothing runs; shows no window |
| Show the Mini Timer when an entry starts | off | After a start from the global shortcut, the menu bar, a notification, an intent, or another device, shows the Mini Timer with the task field focused |
| Show the Mini Timer when an entry stops | off | The same after a stop from those sources |

A start or stop through the commands of a Timer, the main menu, Projects, or Reports shows nothing, and neither does the split at real midnight, which is no start. Window › Mini Timer and the menu bar's "Show Mini Timer" display the show/hide shortcut (none when unassigned); choosing either only shows the Mini Timer.

## 9. Menus and keyboard

The main menu is the same in every window, on the Mac and, with the differences of [spec_ios.md](spec_ios.md) §10.3, on the iPad; the section specs list their sections' commands. As in Music or Mail, these are object menus: File, Edit, View, Timer, Entry, Project, and Window, with Entry and Project acting on what is selected in the view shown.

Every item is always listed; one that applies to a single view is disabled elsewhere, and holds its key equivalent only while enabled, because AppKit sends a key equivalent to the first item that has it, even a disabled one. So one key can serve several views (⌘⌫ deletes a Timer row and a project), and a disabled item never takes a key from a text field. A command several views share is one item acting on the view shown: Find, Continue, Edit Entry…, Delete, Go to Today, Previous and Next Period, and Date Range…. Keys a view handles itself (arrows, Tab, Escape) are not menu items.

File holds New Project…, New Area…, and New Client… ([spec_projects.md](spec_projects.md) §2.5) and Reports' Export…. View holds the sidebar's items, the sidebar toggle, the shown range's navigation, then each view's display options under its own header (Timer, Calendar, Report, Activity), then the Mini Timer's. Undo covers delete, discard, and popover edits. The Project menu is specified in [spec_projects.md](spec_projects.md) §2.5, the Calendar's Entry commands in [spec_calendar.md](spec_calendar.md) §5.

| Menu | Command | Shortcut | Enabled |
|---|---|---|---|
| Edit | Find | ⌘F | Timer, Calendar, Reports, Projects |
| View | Timer, Calendar, Reports, Projects, Activity | ⌘1 to ⌘5 | Always; shows the main window on that item |
| View | Scroll to Today | ⌘↑ | Timer |
| View | Compact Mode (checkmark); Float on Top | ⇧⌘M; none | While the Mini Timer is key |
| Timer | New Entry | ⌘N | Always |
| Timer | Continue | ⌘O | Always: the selection of the view shown (a Timer row; a selected project, titled "Start Timer"; or the one selected Calendar or Reports entry), else the most recent other entry |
| Timer | Stop; Discard Running Entry | ⌘S; ⌥⌘⌫ | Always |
| Timer | Start Pomodoro / Cancel Pomodoro | ⇧⌘P | Always |
| Timer | The next step: End Focus Now, Start Break, End Break Now, or Start Focus | ⌃⌘P | Always; "End Focus Now", disabled, while the Pomodoro is off |
| Entry | Edit Entry… | ⌘E; ↩ in the Calendar | Timer (running entry from the bar, selected row from the list), the Calendar's selection, the Reports list's row |
| Entry | Set Project… | ⌘J | Timer |
| Entry | Delete Entry… | ⌘⌫; Delete in the Calendar | Timer with a selected row in the focused list; the Calendar's selection |
| Window | Mini Timer | The show/hide shortcut, displayed | Always |

"Timer" as scope means the Timer is shown, in the main window or the Mini Timer. The Window menu lists Mini Timer at the top and the main window as `<APP_NAME>` last, each once. Both are the app's own items, because SwiftUI lists a `Window` scene only while another scene is listed too.

## 10. Notifications

The Mac app requests authorization at the first start of an entry. Without it, the confirmation button and the idle sheet still work.

| Category | Title / body | Actions |
|---|---|---|
| `pomodoroFocusDone` | "Focus done" / "25 minutes on Clarify noise model. Time for a break." | Start Break, Skip Break |
| `pomodoroBreakDone` | "Break over" / "Ready for the next focus?" | Start Focus, End Pomodoro |
| `idle` | "You have been away" / "Idle since 14:02 while tracking Clarify noise model." | Keep, Discard, Discard and Continue, Split |
| `reminder` | "Nothing is being tracked" / "Last entry stopped at 13:40." | Start New, Continue Latest, Snooze |

The two Pomodoro categories use bundled sounds with "Play a sound" on; all others use the default sound. Clicking a notification shows the Mini Timer (with the idle prompt for `idle`). Pending Pomodoro and idle notifications are removed when their state resolves elsewhere. A URL's banner is the category `tracking` ([spec_automation.md](spec_automation.md) §6).

## 11. Testable behaviors

- TM-1. Mini Timer height drags snap per §1.1: release at 199 pt gives 106 pt, at 200 pt gives 300 pt, 106 to 250 pt gives 300 pt, with width as dragged (at least 400 pt) and top-left fixed.
- TM-2. ⇧⌘M toggles between the remembered compact and full frames at the current top-left corner; without remembered frames, between 480 × 106 and 480 × 600 pt.
- TM-3. Opened after a relaunch, the Mini Timer has its mode, frame, and pin state from quit; with the pin on it stays above another app's key window.
- TM-4. ⌥⌘R shows the Mini Timer with the task field focused, or hides the app when the Mini Timer is key; Window › Mini Timer displays the recorded shortcut and none when cleared.
- TM-5. Launched as a login item, the app reopens the windows open when it last quit (the closes while it quits don't count), and with none shows no window; quitting leaves a running entry running.
- TM-6. Each action of §2.1 has its effect; ⌘N and Continue stop a running entry at the instant the new one starts; ⌘O without selection continues the most recent other entry.
- TM-7. A task edit of the running entry is stored within 500 ms of the last keystroke; Escape reverts it.
- TM-8. Typing three characters shows at most 8 suggestions, the current project's first; accepting sets task and project.
- TM-9. Typing `@noi` opens the picker searching "noi" with focus in the task field; Return assigns the highlighted project and removes "@noi"; Escape leaves "@noi"; `a@b` opens nothing.
- TM-10. The picker search "noise" lists the project under which "Clarify noise model" was tracked within 90 days.
- TM-11. A project created from the picker is assigned to the running entry, or to the draft.
- TM-12. Discard deletes the running entry after the alert and ⌘Z restores it; continuing an archived project's entry starts nothing unless "Restore Project and Continue" is chosen.
- TM-13. With an entry running since 23:10, at 00:05 the timer label reads `0:55:00`, and the list later shows its two pieces under their own days.
- TM-14. Today's total includes the running entry's elapsed time and rises one second per second; the running entry is Today's first row with its project, and a filter it does not match removes both.
- TM-15. Two identical consecutive entries appear as two rows; the list shows 14 days with entries and "Load Earlier Entries" appends 14.
- TM-16. The list inputs of §3 act as listed.
- TM-17. ⌘F with "noise" leaves only matching entries, and day totals sum them.
- TM-18. The popover recomputes and moves entries per §4.2.
- TM-19. A commit that would put the entry after now is refused with "Entries cannot be in the future"; for the running entry Stop, Duration, and Date are disabled.
- TM-20. Stop 00:35 on an entry starting 23:10 stores two pieces split at midnight and shows "Continues on <next day> until 00:35".
- TM-21. A task change on one piece of a chain changes every piece; a Start change changes only that piece.
- TM-22. An overlapping change shows the inline notice; "Keep" stores it, "Revert" restores the field.
- TM-23. A Pomodoro shows the countdown and a filling ring on the Pomodoro button, then `+0:00` counting up at `focusEnd` with "Focus done" sent and "Start Break" shown on the button; the timer label keeps the elapsed time throughout.
- TM-24. Through a focus, break, and focus cycle the store holds one running entry and no stopped entry.
- TM-25. Every transition of §5.3 holds, including that pending notifications are removed when the state turns off.
- TM-26. A focus duration change during focus does not move `focusEnd`; waking after `focusEnd` lands in `focusOver` and notifies at wake.
- TM-27. With a 10 min threshold, 10 min 5 s without input while an entry runs prompts at the next input with "Idle since" the time input stopped; no prompt while `passive`, when nothing runs, or below the threshold.
- TM-28. The prompt's options act as in §6.3.
- TM-29. Lock, sleep, and shutdown follow the settings of §6.2, using the lock or shutdown time.
- TM-30. With reminders every 10 min, 09:00 to 17:00, weekdays, a reminder arrives 10 min after a stop at 10:00 on a Tuesday, none at 17:05 or on a Saturday; Snooze suppresses them for its duration.
- TM-31. The continue/stop shortcut stops or continues; with "Show the Mini Timer when an entry starts" on, the Mini Timer then appears with the task field focused.
- TM-32. Each notification category offers exactly its listed actions; the settings window reopens on the last pane shown.
- TM-33. The first-launch alert of §8.2 appears once per Mac; "Open Tracker Settings" opens the Tracker pane, and the agent stays unregistered until "Enable Tracker".
- TM-34. The first-launch alert's "Open `<APP_NAME>` at login" checkbox is on by default; checked, either button turns on "Open at login", unchecked neither does; under `-UITesting` the real login item is never registered.
- TM-35. Every window has the menus File, Edit, View, Timer, Entry, Project, and Window; Window lists "Mini Timer" once and the main window once, by the app's name, as its last item. With the Timer shown Entry › Set Project… is enabled and View › Go to Today and the Project menu's items are not. In the Calendar Entry › Duplicate to Next Day and View › Go to Today and Previous Period are enabled, Set Project… is not, and there is no Next Day, Next Entry, or Deselect item. In Projects Project › Edit Project… is enabled for a selected project and File › New Project… always; there is no Start Timer item outside the Timer menu. View › Compact Mode is enabled only while the Mini Timer is key.
- TM-36. The Mini Timer and the main window's Timer are independent: the project picker, an edit popover, the selection, the filter, and a task-field focus request in one leave the other unchanged; a project chosen in one is the project of both; New from the main menu focuses the key window's Timer; a store change reloads both lists. An alert of the Timer shows in the key window, also while the main window shows another item, and with no key window the Mini Timer comes forward with it.
- TM-37. Editing the running entry's Start in the popover, opened from the timer label or the running row, moves the timer label and keeps the task in the popover, the bar, and the row; a task committed before the popover loaded is the stored task, never an empty one; a task typed in the bar just before opening is the popover's task and survives a Start edit; a task changed in the popover shows in the bar.
- TM-38. With "At launch, show" set to Mini Timer, a launch other than a login-item launch shows the Mini Timer instead of the main window, also after the app was killed with the main window and Settings open; the setting persists.
- TM-39. Every settings pane has the same width; the window is shorter on Pomodoro than on General, returns to General's height on going back, and a drag at its corner doesn't resize it.
- TM-40. With no window open (a login-item launch with none open at the last quit), the menu bar's Open `<APP_NAME>`, Show Mini Timer, and Settings… open the main window, the Mini Timer, and the settings window.
- TM-41. A task typed into the running entry less than 500 ms before New, Continue, or Start Timer replaces it is stored on that entry.
- TM-42. With an editor (the Mac popover or the iPhone edit sheet) open on an entry whose Stop another device then changes, editing Start stores the new start and keeps the other device's stop.
- TM-43. Starting an entry, here or on another device, removes a delivered "Nothing is being tracked" reminder, and its Start New and Continue Latest do nothing while an entry runs.
- TM-44. Return accepts no suggestion or picker line loaded for text the user has since typed past; with the `@` picker open it waits for the current lines, assigns the project, and starts nothing.
- TM-45. With Midnight at 04:00, the list's days and their totals are the shown days: an entry across it has a row with its part on each day, a night across real midnight lies on one day, and a row's editor opens the stored entry.
- TM-46. Choosing Midnight in the General pane moves the Calendar's first hour label to that hour, and 00:00 restores it.
- TM-47. A split at real midnight is no change of the running entry: the Mini Timer doesn't show, an open idle prompt stays open and acts on the chain, the Pomodoro's phase stays, and a task being typed stays and commits to every piece.
- TM-48. With "Show the Mini Timer when an entry starts" and "when an entry stops" on, a start or stop from a Timer or the main menu shows nothing, and one from the menu bar, a notification, or another device shows the Mini Timer with the task field focused.
- TM-49. With idle from 23:50 and the prompt answered at 00:30, Split, Discard and Continue, and Discard stop the entry at 23:50 and remove its piece after midnight; Keep changes nothing. A lock stop reaches back the same way.
- TM-50. Tabbing through an unchanged Start or Stop stores nothing, also for times with seconds; an edit in whole minutes keeps the stored seconds.
- TM-51. ⌘J in the edit popover opens the popover's own project picker, and closing the picker leaves the popover open.
- TM-52. Closing the Mini Timer clears its filter and returns its list to the top, so it opens that way again; the main window's Timer keeps its own filter.
