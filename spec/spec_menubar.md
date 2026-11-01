# Spec: Menu Bar Item

The Mac app's status item shows the running entry's elapsed time and, during a Pomodoro, the countdown next to an icon, and its menu starts, continues, and stops entries, drives the Pomodoro, and opens the app's windows. This spec also owns the Dock icon setting and the Dock menu, and the warning when the activity tracker has stopped. State and commands come from the Timer (`spec_timer.md` §13).

## 1. The status item

### 1.1 Content

The item is an `NSStatusItem` (created at launch by the app delegate, with an `NSMenu`): an icon, then optional text (image leading, 4 pt gap) in the menu bar font with monospaced digits. As everywhere (`spec_design.md` §11), the elapsed time is the primary text and the Pomodoro countdown a secondary segment behind its phase glyph.

The icon is the dial, a template image drawn from the app icon's ring and knob (`spec_design.md` §9) on a 16 pt square: a ring (centerline radius 5.4 pt, width 2.3 pt) whose track is drawn at 30% opacity, an opaque arc clockwise from 12 o'clock, and a knob (radius 1.75 pt, with a 0.9 pt clear gap around it) at the arc's end.

| State | Icon | Text |
|---|---|---|
| No running entry | The track alone | None |
| Running entry | A minute hand: the arc and knob at the chain's minutes within the hour (`0:40` is two thirds of a turn; a full hour starts over at 12 o'clock) | Elapsed time, counting up |
| Pomodoro focus | The phase's progress: the arc and knob at the elapsed fraction of the focus | Elapsed time, then the apple glyph (`pomodoro`, `spec_design.md` §5) and the remaining time, counting down |
| Pomodoro break | The break's progress | Elapsed time, then the `cup.and.saucer` glyph and the remaining time |
| Phase ended, confirmation pending | The full ring with the knob at 12 o'clock | Elapsed time, then the ended phase's glyph and `+m:ss`, counting up from the phase end |

The elapsed time is `h:mm` (`0:04`, `13:05`), or `h:mm:ss` with "Show seconds"; hours have no leading zero and grow past 24. It is computed from the running entry's chain start (`spec_data_and_sync.md` 1.5) and the clock, so it does not reset at the midnight split.

With "Show project" on and a project set, the project name follows the time after " · " (`0:40 · Thesis`), truncated with an ellipsis at 24 characters. With "Show timer" off the name stands alone; with both off the item is the icon alone. The task never appears in the menu bar.

The Pomodoro segment follows that text after two spaces: the phase glyph (a text attachment in the menu bar's text color), a thin space, and the countdown, always `m:ss`, led by figure spaces to the width of the phase's full length so the item does not narrow when the minutes lose a digit and shown whatever "Show timer" says (`0:40 · Thesis  ⏲ 12:34`). The "During a Pomodoro, show" setting (6) chooses what the item shows while a Pomodoro is on: "Timer and countdown" as described; "Countdown only" drops the elapsed time, so the segment follows the project name or stands alone (`⏲ 12:34`); "Timer only" drops the segment. The accessibility label always includes the Pomodoro.

While the tracker warning (3) is active, the icon carries a small exclamation-mark badge at its lower right in every state (the image widens to 18 pt, with a clear gap around the badge).

### 1.2 Width, appearance, clicks

The item is exactly as wide as its content. Its `behavior` excludes removal by ⌘-dragging. Icons are template images and the text uses the standard menu bar color; no area color appears. The accessibility label describes the state ("Tracking, 40 minutes, Thesis"; "Not tracking"; ", Pomodoro focus, 12 minutes 34 seconds left" appended during a Pomodoro; ", tracker not running" appended with the warning), and the accessibility title holds the visible text.

A left click and a right click both open the menu, as does the system's "Move focus to status menus" shortcut.

## 2. The menu

```
⚠ Tracker not running since 14:02   (header; only with the warning)
Open Tracker Settings…              (only with the warning)
─────────────────────────────
Clarify noise model                 (header, semibold)
● Noise Model · University          (header; area dot)
◷ Started 13:38 · 0:40 elapsed      (header, secondary color)
⏲ Focus · 12:34 left                (header; only during a Pomodoro)
─────────────────────────────
New                             ⌘N
Continue                        ⌘O
Stop                            ⌘S
─────────────────────────────
Start Pomodoro                 ⇧⌘P  (items per 2.3)
─────────────────────────────
Show Mini Timer                ⌥⌘R  (the recorded show/hide shortcut)
Open TimeTracking
Settings…                       ⌘,
─────────────────────────────
Quit TimeTracking               ⌘Q
```

### 2.1 Header

Consecutive header lines form one disabled menu item whose view (SwiftUI in an `NSHostingView`) keeps their styles, which a disabled item's title would gray out. The view is built when the menu opens and updated in place every second while open, so the refresh neither flickers nor changes the menu's width. The menu is rebuilt only when its items change (compared by value). Its text starts at the menu items' title inset. The first line is flush; the detail lines carry a 14 pt leading column with the area dot or a `.secondary` symbol.

| Situation | Lines |
|---|---|
| Running entry | The task (or "No task") in `.headline`, truncated at 60 characters; the area dot (hollow for no project), the project and " · Client" in `.secondary` (or "No project"); `clock`, `Started HH:MM · h:mm elapsed` in `.secondary`, with "yesterday" or the date after the time when the chain started on an earlier day ("Started 23:10 yesterday · 1:05 elapsed") |
| No running entry | "Not tracking" in `.headline`; then `clock`, `Last: <task>, stopped HH:MM` in `.secondary` if an entry was stopped today |
| Pomodoro on | One more line with the phase glyph (`pomodoro`, `cup.and.saucer`): `Focus · m:ss left`, `Break · m:ss left`, `Focus ended · +m:ss`, or `Break ended · +m:ss` |
| Tracker warning | `exclamationmark.triangle` and the text in orange: "Tracker not running since HH:MM" |

Times use the locale's format; "elapsed" is always `h:mm`.

Command items carry the symbols of `spec_design.md` §5 (New `plus`, Continue `play.fill`, Stop `stop.fill`, the phase glyph on Start Pomodoro, Start Break, and Start Focus, Settings `gearshape`); their `preferredImageVisibility` stays automatic, so the system decides whether menus show them (macOS 27 hides item images by default).

### 2.2 Commands

| Item | Key | Enabled when | Action |
|---|---|---|---|
| New | ⌘N | Always | The Timer's New: starts an empty entry and shows the Mini Timer with the task field focused. |
| Continue | ⌘O | An entry other than the running one exists | Continues the most recent entry other than the running one, without showing a window; an archived project shows the restore alert. |
| Stop | ⌘S | An entry runs | Stops the running entry. |
| Show Mini Timer | the show/hide shortcut | Always | Shows the Mini Timer and activates the app (`spec_timer.md` 8.3). |
| Open `<APP_NAME>` | | Always | Shows the main window on its current item and activates the app. |
| Settings… | ⌘, | Always | Opens the settings window on its last pane. |
| Quit TimeTracking | ⌘Q | Always | Quits; the running entry keeps running. |

Each item has a main-menu counterpart with the same key equivalent and calls the same command.

### 2.3 Pomodoro items

The group offers what the state machine (`spec_timer.md` 5.3) allows and performs it directly.

| Pomodoro state | Items |
|---|---|
| off | Start Pomodoro ⇧⌘P (disabled while nothing runs) |
| focus | End Focus Now ⌃⌘P; Cancel Pomodoro ⇧⌘P |
| focusOver | Start Break ⌃⌘P; Skip Break; Cancel Pomodoro ⇧⌘P |
| break | End Break Now ⌃⌘P; Cancel Pomodoro ⇧⌘P |
| breakOver | Start Focus ⌃⌘P; Cancel Pomodoro ⇧⌘P |

## 3. Tracker warning

The app checks every 30 seconds and at wake, unlock, and launch. The warning is active when the tracker's login item is registered and enabled, the tracker is not running (`spec_activity_tracking.md` §4.4), and the Mac has been awake, unlocked, and in the user's session for at least the last 2 minutes. A tracker that is not enabled gives no warning.

While active, the icon carries the badge and the menu starts with the warning header "Tracker not running since HH:MM" (the `last_tick` time, or "Tracker not running" without a file) and "Open Tracker Settings…", which opens the settings window on the Tracker pane. Problems of individual sources appear only in the Tracker pane. The first check that finds the tracker running clears the warning.

## 4. Dock icon and Dock menu

"Show Dock icon" sets the activation policy at launch and on every change, without relaunch.

| Show Dock icon | Policy | Consequences |
|---|---|---|
| On (default) | Regular | Dock tile with a Dock menu; in ⌘-Tab. Clicking the tile shows the main window. |
| Off | Accessory | No Dock tile, not in ⌘-Tab; windows open normally and the main menu shows while one is key. |

The app keeps running when its last window closes. Switching to accessory with a window open re-activates the app so the window that was key (the settings window, when the change comes from there; else the main window or the Mini Timer) stays key and in front. The Dock menu has "New Entry", "Continue Latest", and "Stop", with the enablement and actions of 2.2.

## 5. Refresh

| Condition | Tick | Alignment |
|---|---|---|
| Nothing runs, no Pomodoro | None | |
| Running, seconds off, no Pomodoro | 60 s | The chain start's second |
| Running, seconds on | 1 s | The chain start's fraction of a second |
| Pomodoro on | 1 s | The phase end |
| Menu open with an entry or Pomodoro | 1 s while open | |

A tick re-reads the clock; nothing is accumulated. Ticks run in the common run loop modes with 100 ms tolerance. The item also re-renders at once on any change of the running entry or Pomodoro state (local or synced), a settings change, a warning change, and a clock or time zone change. Sleep cancels the tick; wake and unlock re-render from the clock and re-arm it.

## 6. Settings

Device settings, edited in Settings > General (`spec_timer.md` 8.1).

| Setting | Key | Default | Effect |
|---|---|---|---|
| Show timer in menu bar | `menuBar.showTimer` | on | Elapsed time next to the icon |
| Show seconds | `menuBar.showSeconds` | off | `h:mm:ss`; indented under "Show timer", disabled while it is off |
| Show project in menu bar | `menuBar.showProject` | off | Project name after the time |
| During a Pomodoro, show | `menuBar.pomodoroDisplay` | Timer and countdown | `both`, `countdown` (Countdown only), or `timer` (Timer only); 1.1 |
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

## 8. Decisions

- The icon is the dial rather than an SF Symbol such as `stopwatch`: it ties the item to the app icon, and it carries information on its own (the minutes, or the Pomodoro's progress) when the text is off.
- An `NSStatusItem` rather than `MenuBarExtra`, for control of the text's font features, clicks, and removal.
- Both clicks open the menu; the global shortcut already shows the Mini Timer.
- Seconds are hidden by default; the Pomodoro countdown always shows them.
- The Pomodoro countdown is a segment after the elapsed time, as on the Timer's Pomodoro button, so the running entry's duration stays visible by default; "During a Pomodoro, show" trades either one away for a narrower item.
- The header is a hosted view rather than disabled items, which AppKit draws grayed out and without the area color.
- The menu bar warns only about a stopped tracker, which loses data.
- New starts the entry at once; the task can follow.
- The item cannot be removed, so an accessory-mode app stays reachable.

## 9. Interfaces

Assumed from `spec_timer.md`: the timer display state (running entry, chain start, most recent other entry, today's last stopped entry, Pomodoro state and phase end), the commands, the restore alert, and the recorded show/hide shortcut.

Assumed from `spec_timer.md` §1: showing the main window on its current item and showing the Mini Timer.

Assumed from `spec_activity_tracking.md`: `current.json` with `health.last_tick` (via `ActivityReading.currentState()`) and the login item's status.

Provided: the settings of §6 and their semantics, the activation policy, and the Dock menu.
