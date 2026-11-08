# Set up the activity tracker

The tracker is an optional background program that [records where your attention goes](../explanation/privacy.md) on the Mac. Nothing is recorded until you finish the first step below.

```{figure} /images/mac-settings-tracker.png
:alt: The Tracker pane of the settings window, with the status line, the Enable Tracker button, and the setup steps.
:width: 460px
:align: center

The Tracker pane lists each step with a mark.
```

## Turn it on

1. Open Settings (⌘,) and click Tracker, or click "Open Tracker Settings" in the sheet at first launch.
2. Click "Enable Tracker". If macOS asks you to approve the login item, click "Open Login Items" and turn it on there.
3. Under Accessibility, which is required, click "Open System Settings" and "Show TimeTrackingAgent in Finder". Drag `TimeTrackingAgent` from the Finder window into the list under Privacy & Security, Accessibility, and turn it on.

The status line turns green with "Tracker running". Without Accessibility access the tracker records app names only.

## Add detail

Each further row says what you gain, on a line starting "On:", and what the tracker does without it, on a line starting "Off:". All of them are optional.

Automation lets the tracker read browser tabs and terminals. Click "Ask for Access" while your browsers and terminals are open, since macOS can ask only about open apps.

Full Disk Access adds browser history and the macOS app usage history, which also fills in time when the tracker wasn't running. Grant it to the app, as the row describes, then click "Restart Tracker".

The rows for Neovim, tmux, Claude Code, and remote shells offer a snippet for those programs' configuration. Click Copy Snippet and paste it into the file the info popover names. The app never installs these for you.

## Check that it works

Work for a few minutes, then open Activity (⌘5). The footer shows the tracker's status and names any source that is limited or off, and the Calendar's Activity column starts filling up.

If the menu bar dial ever shows an exclamation mark, the tracker has stopped. Open the menu and choose "Open Tracker Settings…".

## Turn it off

Click "Disable Tracker" in the same pane. What is already recorded stays, and the iPhone and iPad keep showing it. The time the tracker is off stays empty, also after you turn it on again.

To change what it records, see [Keep something out of the activity record](exclude.md). The settings file also holds further options, which the [tracker spec](../reference/activity_tracking.md#7-settings-and-exclusions) lists.
