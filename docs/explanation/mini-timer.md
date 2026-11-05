# The Mini Timer

The Mini Timer keeps the Timer next to whatever else you are doing, the way the MiniPlayer does for Music. It is a small second window with the same bar, list, and editor as the main window, plus a pin and a compact mode.

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item}
```{figure} /images/mac-mini-timer.png
:alt: The Mini Timer window in full mode, with the running-entry bar above the list of entries.

Full mode.
```
:::

:::{grid-item}
```{figure} /images/mac-mini-timer-compact.png
:alt: The Mini Timer in compact mode, showing only the running-entry bar.

Compact mode, just the bar.
```
:::
::::

Press ⌥⌘R from any app to show it with the cursor in the task field, ready to type. Press the same keys while it is in front to hide it again. You can change that shortcut in Settings, under Shortcuts. It is also in the Window menu and in the menu bar item's menu.

## Full and compact

The window's mode follows its height. Drag the bottom edge below 200 points and the list disappears, leaving only the bar. When you let go, the window settles at the compact height, or at the smallest full height if you stopped above the threshold. ⇧⌘M switches between the two, keeping the top-left corner where it is and restoring each mode's remembered size.

## Floating above other windows

The pin at the top right of the window, also View › Float on Top, keeps the Mini Timer above other apps' normal windows. The setting survives relaunches. A pinned window doesn't join other apps' full-screen spaces.

## Independent of the main window

The Mini Timer and the main window's Timer are two views of the same data. Each has its own selection, filter, and scroll position, so filtering one leaves the other alone, and a project chosen in one is the project of both. When you close the Mini Timer, its filter clears and its list returns to the top.

## Making it appear on its own

Two settings under Shortcuts show the Mini Timer when an entry starts or stops, for example from the global shortcut, the menu bar, a notification, or another device. They exist for people who want to name the task right after a start they didn't make at the keyboard. A start from a Timer window, a URL, or the command-line tool shows nothing.

The setting "At launch, show" in the General pane makes the Mini Timer, rather than the main window, your starting point. The [Timer spec](../reference/timer.md#1-windows) lists the exact sizes.
