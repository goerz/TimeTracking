# The menu bar

The dial at the top right of your screen shows what is running without any window open, and its menu reaches every main command.

```{figure} /images/mac-menu-bar.png
:alt: The app's menu open under its menu bar item, with the running entry at the top, then New, Continue, Stop, Pomodoro items, and commands to open the app's windows.
:width: 340px
:align: center

The menu starts with the running entry and its project.
```

## What the item shows

The dial is the app's icon reduced to one color: a ring with a knob. With nothing running it is an empty ring. With an entry running, the knob moves like a minute hand and the elapsed time stands next to it, such as `0:40`, which keeps counting past a day boundary because it counts from the entry's real start. During a Pomodoro the ring shows the phase's progress instead, and a small segment with the countdown follows the time.

You choose how much appears in Settings, under General, in the section "Menu bar and Dock". "Show timer" and "Show seconds" set the time, "Show project" adds the project name, and "During a Pomodoro, show" trades the elapsed time or the countdown away for a narrower item. With everything off the item is the bare dial, which still shows the minutes. The task never appears in the menu bar.

## The menu

A left click or a right click opens the menu. Its first lines describe the moment: the task, the project and client with its area color, and "Started 09:10 · 0:40 elapsed", or "Not tracking" and your last entry of the day. Then come New, Continue, and Stop, the Pomodoro actions that apply right now, then Show Mini Timer, Open, Settings…, and Quit.

New starts an empty entry at once, since the task can follow, and shows the Mini Timer with the cursor in its task field. Continue starts your most recent entry again without showing any window. Quit leaves a running entry running.

## The tracker warning

If you enabled the tracker, it is not running, and the Mac has been awake and unlocked for at least two minutes, the dial gets a small exclamation mark and the menu starts with "Tracker not running since" and a time, followed by "Open Tracker Settings…". The warning appears only for a stopped tracker, because that is what loses data. Problems with a single source show only in the Tracker pane.

## The Dock

"Show Dock icon" is on by default. Turn it off and the app leaves the Dock and the ⌘-Tab switcher without a relaunch, living in the menu bar only; windows still open normally. With the Dock icon on, its menu offers New Entry, Continue Latest, and Stop.

The [menu bar spec](../reference/menubar.md) has the complete tables.
