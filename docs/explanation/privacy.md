# What the tracker records

The tracker is off until you turn it on. Nothing is recorded before you click "Enable Tracker" in the Tracker pane of the settings, and the iPhone and iPad collect nothing until you turn on collection on that device.

## On the Mac

Once enabled, the tracker takes a sample every 30 seconds, and at once when you switch apps or tmux panes or lock the screen. A sample holds the time, whether you are present, and what has your attention: the app and its window, the terminal session, the folder or web address, the files open in an editor, the command running in the terminal, and the project folder or site the work belongs to.

It reads this from window titles, browser tabs, terminal sessions, and the macOS app usage history, as far as you grant the permissions. Each source has a fallback. Without Accessibility access the tracker records only app names; without Full Disk Access it records Safari pages by site only. The Tracker pane shows which sources are on, limited, or off, and what each one costs you.

Some things are never recorded: keystrokes, the clipboard, screenshots, message bodies, password manager contents, and anything of a private browser window beyond the browser's name. Command lines and web addresses can carry passwords and tokens, so before they leave the Mac, the tracker replaces the parts that look like secrets with `(private)`.

## What leaves the Mac

The samples stay on the Mac, in a local database, for 90 days. From them the tracker forms the block log: for each stretch of activity, its time and every item with its seconds, with secrets removed as described above. The block log goes to iCloud Drive, so your iPhone and iPad can show it.

The only other thing that leaves is the Mac's current activity, a single line, so your iPhone can show what the Mac is doing.

All of this stays within your own iCloud account.

## Exclusions

You decide what the tracker may see. Exclusions apply where data enters, before anything is written, and they range from mild to total. An excluded folder keeps its time but hides its name as `(private)`. An excluded app records nothing at all, and the time becomes a gap. A private domain is recorded by its domain only; an excluded domain is recorded as a private browser window.

The Calendar and Activity also apply your current rules to the past when they show it, so a new exclusion hides old data at once. The log files keep what they hold until you rewrite them. [Keep something out of the activity record](../howto/exclude.md) shows how.

## On the iPhone and iPad

The system allows no such observation there, so collection is coarser and entirely opt-in, per device. Screen Time reports how many minutes you spent in groups of apps you define, without naming the apps. A Safari extension can record sites. Focus modes and Shortcuts automations can add events. Query strings, fragments, and page titles are never stored.

[Collect activity on iPhone and iPad](../howto/ios-activity.md) walks through it, and the [tracker reference](../reference/activity_tracking.md) lists every source and rule.
