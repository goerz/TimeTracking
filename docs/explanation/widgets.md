# Widgets and controls

Widgets put the running entry on the iPhone and iPad Home Screen and Lock Screen, where a glance replaces opening the app. Their buttons work directly: Stop stops the entry without opening anything. There are no widgets on the Mac, where the [menu bar item](menu-bar.md) does this job.

```{figure} /images/iphone-widgets.png
:alt: An iPhone Home Screen with the Now, Recent, and Pinned widgets.
:width: 300px
:align: center

Now, Recent, and Pinned on the Home Screen.
```

## The three widgets

Now shows the running entry with its live elapsed time and a Stop button, or, while idle, "Not tracking" with today's total and your latest entry to continue. Its medium size adds today's total and a line about what your Mac is doing. During a Pomodoro, a second line under the elapsed time shows the phase and the time left.

Recent lists your last entries, each with a Continue button, in three sizes from 3 to 14 rows. While something runs, the first row is the running entry with Stop.

Pinned is a grid of start buttons for your favorite projects: 2, 4, 8, or 12 by size. It shows the projects you pinned in Settings, or a list chosen for that one widget. Each button starts its project, with the project's last task or none, as you prefer. The running project's button takes a light tint and stops it instead.

## Lock Screen

Three small families work on the Lock Screen. The inline one shows "12:34 · Project" and opens the app. The circular and rectangular ones show the live time, and their button stops the entry or continues your latest one. All buttons require unlocking first, so nothing changes on a locked phone in someone's hand. Task text counts as private, so the system hides it when you have asked it to hide widget content while locked.

## Controls

The Timer control for Control Center is a toggle: on exactly while an entry runs. Turning it on continues your latest entry, and turning it off stops the running one. The Start Project control is a button that always starts one chosen project, which suits the Action button.

## Keeping up

Widgets can't run on their own, so the app works around that. Your Mac sends a push to the widgets whenever the running entry changes, and they fetch the current state directly from iCloud. With the Mac app running and online, a stop on any device reaches a Home Screen widget in about five seconds. Without the Mac, local changes still update the widgets at once, and changes from another iOS device arrive more slowly. [How your devices stay in step](sync.md) explains why.

The steps are in [Add widgets and controls](../howto/widgets.md), and the [iOS spec](../reference/ios.md#3-widgets) lists each family's content.
