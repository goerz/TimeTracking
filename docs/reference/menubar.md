# Menu Bar Item

The Mac app's status item shows the running entry's elapsed time and, during a Pomodoro, the countdown. Its menu drives the Timer's commands ([timer.md](timer.md)) and opens the app's windows. This spec also covers the Dock icon setting, the Dock menu, and the warning when the activity tracker has stopped.

## 1. The status item

### 1.1 Content

The item is an `NSStatusItem`, for control of its text, clicks, and removal: an icon, then optional text in the menu bar font with monospaced digits. The icon is the dial, a template image drawn from the app icon's ring and knob ([design.md](design.md) §9): a faint track, an opaque arc clockwise from 12 o'clock, and a knob at its end. The dial carries information of its own when the text is off.

| State | Icon | Text |
|---|---|---|
| No running entry | The track alone | None |
| Running entry | The entry's minutes within the hour, like a minute hand (`0:40` is two thirds of a turn) | Elapsed time |
| Pomodoro focus or break | The elapsed fraction of the phase | Elapsed time, then the phase glyph (`pomodoro`, `cup.and.saucer`) and the remaining time |
| Phase ended, confirmation pending | The full ring with the knob at 12 o'clock | Elapsed time, then the ended phase's glyph and `+m:ss`, counting up from the phase end |

The elapsed time is `h:mm` (`0:04`, `13:05`), or `h:mm:ss` with "Show seconds"; hours grow past 24. It counts from the running entry's start ([data_and_sync.md](data_and_sync.md) 1.5), so it does not reset at midnight.

With "Show project" on and a project set, the project name follows the time after " · " (`0:40 · Thesis`), truncated with an ellipsis at 24 characters. With "Show timer" off the name stands alone; with both off the item is the icon alone. The task never appears in the menu bar.

The Pomodoro segment follows that text, so the entry's duration stays visible by default. Its countdown is always `m:ss`, led by figure spaces to the width of the phase's full length so the item does not narrow when the minutes lose a digit, and it shows whatever "Show timer" says. "During a Pomodoro, show" (6) trades either part away for a narrower item: "Countdown only" drops the elapsed time, "Timer only" the segment. The accessibility label always includes the Pomodoro.

While the tracker warning (3) is active, the icon carries a small exclamation-mark badge in every state.

### 1.2 Width, appearance, clicks

The item is exactly as wide as its content and can't be removed by ⌘-dragging, so an accessory-mode app stays reachable. No area color appears. The accessibility label describes the state ("Tracking, 40 minutes, Thesis"; "Not tracking"; ", Pomodoro focus, 12 minutes 34 seconds left" and ", tracker not running" appended).

A left click, a right click, and the system's "Move focus to status menus" shortcut all open the menu; the global shortcut already shows the Mini Timer.

## 2. The menu

From the top, in groups separated by lines: the tracker warning (3), the header (2.1), New, Continue, and Stop, the Pomodoro items (2.3), then Show Mini Timer, Open `<APP_NAME>`, and Settings…, and last Quit `<APP_NAME>`.

### 2.1 Header

The header lines form one disabled item with a hosted view, because AppKit grays out a disabled item's title and drops the area color. While the menu is open the view updates in place every second, so the refresh neither flickers nor changes the menu's width.

| Situation | Lines |
|---|---|
| Running entry | The task (or "No task"), truncated at 60 characters; the area dot (hollow for no project), the project and " · Client" (or "No project"); `Started HH:MM · h:mm elapsed`, with "yesterday" or the date after the time when the entry started on an earlier calendar date ("Started 23:10 yesterday · 1:05 elapsed") |
| No running entry | "Not tracking"; then `Last: <task>, stopped HH:MM` if the latest stopped entry lies on the current day of the "Start of day" setting |
| Pomodoro on | One more line with the phase glyph: `Focus · m:ss left`, `Break · m:ss left`, `Focus ended · +m:ss`, or `Break ended · +m:ss` |
| Tracker warning | An orange `exclamationmark.triangle` and "Tracker not running since HH:MM" |

"Yesterday" compares plain dates, whatever the "Start of day" setting says, because the line states when the entry started by the clock. Times use the locale's format.

### 2.2 Commands

| Item | Key | Enabled when | Action |
|---|---|---|---|
| New | ⌘N | Always | Starts an empty entry at once, since the task can follow, and shows the Mini Timer with the task field focused |
| Continue | ⌘O | An entry other than the running one exists | Continues the most recent such entry without showing a window; an archived project shows the restore alert |
| Stop | ⌘S | An entry runs | Stops the running entry |
| Show Mini Timer | The show/hide shortcut | Always | Shows the Mini Timer and activates the app |
| Open `<APP_NAME>` | | Always | Shows the main window on its current item and activates the app |
| Settings… | ⌘, | Always | Opens the settings window on its last pane |
| Quit `<APP_NAME>` | ⌘Q | Always | Quits; the running entry keeps running |

### 2.3 Pomodoro items

The group offers what the state machine ([timer.md](timer.md) 5.3) allows and performs it directly.

| Pomodoro state | Items |
|---|---|
| off | Start Pomodoro ⇧⌘P (disabled while nothing runs) |
| focus | End Focus Now ⌃⌘P; Cancel Pomodoro ⇧⌘P |
| focusOver | Start Break ⌃⌘P; Skip Break; Cancel Pomodoro ⇧⌘P |
| break | End Break Now ⌃⌘P; Cancel Pomodoro ⇧⌘P |
| breakOver | Start Focus ⌃⌘P; Cancel Pomodoro ⇧⌘P |

## 3. Tracker warning

The menu bar warns only about a stopped tracker, which loses data; problems of individual sources appear only in the Tracker pane. The app checks every 30 seconds and at wake, unlock, and launch. The warning is active when the tracker's login item is enabled, the tracker is not running ([activity_tracking.md](activity_tracking.md) §4.4), and the Mac has been awake, unlocked, and in the user's session for at least 2 minutes.

While active, the icon carries the badge and the menu starts with "Tracker not running since HH:MM" (the `last_tick` time of `current.json`, or "Tracker not running" without a file) and "Open Tracker Settings…". The first check that finds the tracker running clears the warning.

## 4. Dock icon and Dock menu

"Show Dock icon" (on by default) sets the activation policy at launch and on every change, without relaunch. On, the app has a Dock tile, whose click shows the main window, and appears in ⌘-Tab. Off (accessory), it has neither; windows open normally and the main menu shows while one is key.

The app keeps running when its last window closes. Switching to accessory keeps an open key window key and in front. The switch deactivates the app asynchronously, so a deactivation within 300 ms of it takes activation back; a deliberate switch to another app takes longer and stands.

The Dock menu has "New Entry", "Continue Latest", and "Stop", with the enablement and actions of 2.2.

## 5. Refresh

The item ticks every 60 s while an entry runs, aligned to the entry start's second, and every 1 s with seconds on (aligned to the entry's start), during a Pomodoro (aligned to the phase end), and while the menu is open. With nothing running it doesn't tick. A tick re-reads the clock; nothing is accumulated. The item also re-renders at once on any change of the running entry or Pomodoro state (local or synced), a setting, or the warning. Sleep cancels the tick; wake and unlock re-render from the clock and re-arm it.

The Mac app looks every minute and reloads when the shown day has changed, so the running entry's part moves to the new day, and it also reloads on wake and on a clock or time zone change.

## 6. Settings

Device settings in Settings > General, section "Menu bar and Dock".

| Setting | Key | Default | Effect |
|---|---|---|---|
| Show timer | `menuBar.showTimer` | on | Elapsed time next to the icon |
| Show seconds | `menuBar.showSeconds` | off | `h:mm:ss`; disabled while "Show timer" is off |
| Show project | `menuBar.showProject` | off | Project name after the time |
| During a Pomodoro, show | `menuBar.pomodoroDisplay` | Timer and countdown | `both`, `countdown` (Countdown only), or `timer` (Timer only) |
| Show Dock icon | `showDockIcon` | on | Activation policy (4) |

## 7. Testable behaviors

- MB-1. With nothing running, the title is empty, the icon is the empty dial, and no tick is scheduled.
- MB-2. With an entry started at T, at T + 4 min 33 s the title is `0:04` (seconds off) or `0:04:33` (seconds on); at T + 25 h it is `25:00`.
- MB-3. With an entry running since 23:10, at 00:05 the title is `0:55`.
- MB-4. With "Show project" on and a 30-character name, the title ends in " · " and 24 characters including the ellipsis; with "Show timer" and "Show project" off, the title is empty and the dial shows the minutes (40 minutes: two thirds of a turn).
- MB-5. A 25-minute focus phase keeps the elapsed time as the title and adds the segment `pomodoro` `25:00`, also with "Show timer" off; two minutes past `focusEnd` without confirmation the segment shows `+2:00` and the menu offers "Start Break".
- MB-6. The header lines follow 2.1 for a running entry, no entry, and a Pomodoro, with their styles and symbols.
- MB-7. Command enablement and actions follow 2.2; Continue shows no window, and New shows the Mini Timer with its task field focused.
- MB-8. Show Mini Timer displays the recorded show/hide shortcut and none when it is cleared; Open `<APP_NAME>` has no key equivalent.
- MB-9. In each Pomodoro state the menu has exactly the items of 2.3, and "Start Break" in `focusOver` moves the state to `break`.
- MB-10. Turning "Show Dock icon" off switches to accessory without relaunch and keeps an open window key; turning it on restores the Dock tile; the Dock menu items match 2.2's enablement.
- MB-11. Ticks follow §5; after a simulated 2 h sleep the first render after wake includes the 2 h.
- MB-12. A running-entry change from sync updates the item without waiting for a tick.
- MB-13. Left and right clicks both open the menu.
- MB-14. With the tracker enabled, `last_tick` 3 minutes old, and the Mac awake for 10 minutes, the badge and the warning lines appear and "Open Tracker Settings…" opens the Tracker pane; awake for only 1 minute, or with the tracker not enabled, there is no warning; a fresh tick clears it.
- MB-15. During a focus phase with "Countdown only" the title is empty (or the project name with "Show project" on) and the segment `pomodoro` `25:00` remains; with "Timer only" the title is the elapsed time and there is no segment; both show the elapsed time again once the Pomodoro is off.
- MB-16. With the menu open, the per-second refresh of an unchanged menu keeps every item and the menu's width; only the header view updates.
- MB-17. The dial is the empty ring with nothing running, a minute hand while an entry runs (95 min 20 s: 35/60 of a turn), the phase's progress during a Pomodoro (10 minutes into a 25-minute focus: 0.4), and the full ring once the phase has ended; with "Show timer" off the item still ticks each minute; the image is a 16 pt template, 18 pt wide with the badge.
- MB-18. The countdown keeps the width of its phase's full length: 9:59 left of a 25-minute focus reads ` ` + `9:59` (a figure space first); a 5-minute break needs no padding.
- MB-19. An entry started at 23:30 that runs while the Mac sleeps past midnight stays one entry, the item counts from its start, and the wake shows its part under the new day; a time zone change reloads the same way.
- MB-20. With the start of day at 04:00, the "Last:" line names an entry from 03:00 to 05:00 today.
