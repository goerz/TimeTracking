# The Timer

The Timer is the everyday surface of the Mac app: what is running now on top, your recent entries by day below. It is the first item in the main window's sidebar (⌘1), and the [Mini Timer](mini-timer.md) shows the same thing in a small window of its own.

```{figure} /images/mac-timer.png
:alt: The main window showing the Timer, with the running-entry bar beside the list of entries grouped by day.

In a wide window the running-entry bar and the list sit side by side; in a narrow one the bar moves above the list.
```

## The running-entry bar

From left to right, the bar holds the Pomodoro button, the task field, the elapsed time, the start or stop button, and, while something runs, a small × that discards the entry. Below them sits the project chip.

While nothing runs, the task field holds a draft. Press Return or the start button and an entry starts with that text and the chip's project, and both may be empty. While an entry runs, the field edits its task: your typing is stored half a second after the last keystroke, so there is nothing to confirm.

From the first character, a popup offers up to eight earlier tasks with their projects, and accepting one sets both. Typing `@` at the start of the field or after a space opens the project picker without leaving the keyboard: `@noi` searches for projects matching "noi", and Return assigns the highlighted one and removes the `@noi` from your text.

The elapsed time always counts from the running entry's real start. A click on it opens the entry's editor.

## Starting, stopping, continuing

Every start stops whatever runs, at the same instant, so no two entries run at once and nothing falls into a gap.

| You want to | Do this |
|---|---|
| Start with what is in the field | Return, or the start button |
| Start a new empty entry | ⌘N |
| Stop | ⌘S, or the stop button |
| Repeat an earlier task | Double-click its row, click its ▶, or select it and press ⌘O |
| Continue your latest task | ⌘O with nothing selected |
| Throw away the running entry | ⌥⌘⌫, or the × button, then confirm |

Continuing always makes a new entry and leaves the old one as it was. The list therefore shows each stretch of work on its own row, also when two in a row are identical.

## The list

Rows are grouped under "Today", "Yesterday", and then dates, each with its day total. The day boundaries follow the [start of day](start-of-day.md). The running entry is the first row of its day, and today's total ticks along with it. The list loads the 14 most recent days that have entries; "Load Earlier Entries" appends 14 more.

Clicking a row opens its editor, and double-clicking continues it. ⌘F shows a filter field: only entries whose task, project, client, or area contains the text remain, and the day totals then sum just those.

## The editor

The same popover edits an entry in the Timer, the Calendar, and Reports. It has Task, Project, Start, Stop, Duration, and Date, and it stores each field as you press Return or leave it. Times are forgiving: `9:1` reads as 09:10, and Duration accepts `25m`, `1h 30m`, `1:30`, or `90s`.

Editing Start keeps Stop in place, and editing Stop or Duration keeps Start. Changing the Date moves the entry by whole days. A change that would put any part of the entry after the current moment is refused, because entries can't lie in the future. A change that overlaps another entry shows a notice with Keep and Revert. [Correct your time](../howto/correct-entries.md) walks through the common cases.

## The rest of the Mac app

The main window's sidebar also holds the [Calendar](calendar.md) (⌘2), [Reports](reports.md) (⌘3), [Projects](projects.md) (⌘4), and [Activity](activity.md) (⌘5). The menu bar at the top of the screen has the same menus in every window: File, Edit, View, Timer, Entry, Project, and Window. Commands that don't apply to the view shown are grayed out rather than hidden.

Closing the window keeps the app running, and quitting doesn't stop the running entry. The Timer spec has [all commands and keys](../reference/timer.md#9-menus-and-keyboard).
