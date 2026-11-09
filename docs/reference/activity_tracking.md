# Activity Tracking Component

## 1. Scope

The tracker records where the user's attention goes, in detail on the Mac and more coarsely on iPhone and iPad, as activity blocks ("blocks"), which the Calendar and the Activity section show. It records raw identifiers (apps, sessions, paths, URLs), never assigns a project, area, or client (the user does that when making entries from blocks in the Calendar), and never reads or writes time entries. It runs on the Mac as the tracker agent, a login item (section 5), with no UI of its own beyond the Mac app's settings pane (7.4). The iOS collectors are in [ios.md](ios.md) §9.

Storage knows one day boundary, 00:00 of the local clock: a block belongs to the date it starts on, even when it runs past midnight. The start of day ([data_and_sync.md](data_and_sync.md) §8) changes only how readers group days.

## 2. Design

### 2.1 Overview

The agent observes the Mac every 30 seconds and at every change, and stores each observation as a *Sample*: a time, a device, a presence state, one *foreground Item* for what the user attends to, and any number of *background Items* for work going on without attention, such as a busy coding agent or a running build. The iPhone and iPad take no Samples. Their TimeTracking app uploads events to CloudKit, which the agent turns into Samples of the same form. Blocks are formed from the Samples alone and written to the *block log*, one file per date.

```{raw} html
:file: figures/activity_tracking_loops.svg
```

{.tt-caption}
Figure 1. The agent's loops. On the Mac, three loops and one request handler run in the agent, one step at a time. A loop runs its numbered steps in order on each pass; a step with a cadence runs only on the passes where it is due. Every write marks the dates it changed, and that set wakes the rebuild loop, the only message between loops. Each pass of the rebuild loop takes one changed date D, the oldest first and today last, and forms the blocks that start on D. The iPhone and iPad run none of this: their TimeTracking app uploads DeviceEvents to CloudKit, and Safari's own iCloud sync brings their visits into the Mac's `History.db`.

The local activity loop (2.4) records the Mac, the remote activity loop (2.5) brings in the iPhone and iPad, the request handler (2.6) deletes and re-filters on the user's request, and the rebuild loop (2.7) forms blocks.

Principles:

1. Attention, not activity. Presence comes from input and the display, never from what apps do: tabs reloading after a display wake are not attention.
2. One stream of attention. Blocks never overlap; the iPhone and iPad fill the time away from the Mac rather than forming a parallel track.
3. Blocks are derived. Every change to the Samples re-forms the dates it touches, so a late iPhone event changes a date's blocks as if it had arrived on time.
4. Privacy where data enters. Exclusions (7.2) apply before a Sample is written. Samples stay on the Mac; only the block log and the current activity, both redacted (4.3), leave it. Never recorded: keystrokes, clipboard, screenshots, message bodies, password manager contents, and anything of a private browser window beyond the browser's name.
5. Degrade instead of failing. Every source that depends on a permission, configuration, or an undocumented format has a fallback and reports its status (3.5).

(tracking-records)=
### 2.2 Records

```{mermaid}
classDiagram
  direction TB
  class Sample {
    <<samples.sqlite>>
    time : Date
    device : String
    source : Source
    state : State
    foreground : Item, optional
    background : Item, 0 or more
  }
  class Item {
    app : String
    appID : String
    window : String, optional
    host : String, optional
    session : String, optional
    location : String, optional
    documents : String, 0 or more
    command : String, optional
    workspace : String
  }
  class Block {
    <<block log>>
    start : Date
    end : Date
    endReason : EndReason, optional
    reconstructedSeconds : Int
    foreground : BlockItem, 0 or more
    background : BlockItem, 0 or more
  }
  class BlockItem {
    device : String
    item : Item
    seconds : Int
  }
  class DeletedRange {
    <<meta>>
    start : Date
    end : Date
  }
  class DeviceEvent {
    <<CloudKit>>
    deviceID : String
    deviceName : String
    time : Date
    utcOffset : Int
    source : screenTime, focus, intent, webext, app
    label : String
    kind : String
    payload : JSON, optional
    sequence : Int
  }
  class State {
    <<enumeration>>
    active
    passive
    idle
    locked
    asleep
    otherUser
    paused
  }
  class Source {
    <<enumeration>>
    live
    appUsage
    safariHistory
    screenTime
    webext
    intent
    app
    focus
  }
  class EndReason {
    <<enumeration>>
    idle
    locked
    asleep
    otherUser
    paused
    split
    maxLength
    stopped
  }
  DeviceEvent ..> Sample : converted by the remote activity loop
  Sample *-- Item : foreground, background
  Block *-- BlockItem : foreground, background
  BlockItem *-- Item : item
  Item .. State
  Item .. Source
  Item .. EndReason
```

{.tt-caption}
Figure 2. The six records, and below them the three enumerations their attributes use. "Optional" may be absent; "0 or more" is a list. A filled diamond marks an object held inside another; the tag above a name says where it is stored, or that it is an enumeration.

- Sample (`samples.sqlite`, 90 days): one observation of one device at one moment.
  - The device is an identifier: the Mac's hardware UUID, or an iPhone's or iPad's `deviceID`. A synced Safari visit takes the `deviceID` of the iOS device whose `deviceName` matches the name `CloudTabs.db` gives, else that name, or `remote` (6.1). Writing a block, the agent names each device by its current name (the Mac's computer name; for an iOS device, the latest `deviceName`, which `meta` keeps by `deviceID`), so renaming a device changes no Sample; a new name marks every date that holds Samples of that device.
  - The source says where it came from: `live` (a pass of the local activity loop), `appUsage` (rebuilt from macOS app usage for time the agent didn't run, 2.4), `safariHistory` (a visit synced from another device, 6.1), or, from an iPhone or iPad, `screenTime`, `webext` (a Safari tab), `intent` (an automation), `app` (TimeTracking itself), and `focus` (a Focus that pauses collection) (6.2).
  - The state `active` is attention with input; `passive` is attention without input, such as a meeting or a video; `idle` is no input for `idle_after` (2 min); `locked`, `asleep`, and `otherUser` (another user owns the screen) are the Mac's; `paused` comes from a Focus (6.2). A change of state takes a Sample at once, so the Samples mark the moment it happened.
  - A Sample is attentive when its state is `active` or `passive` and it has a foreground Item.
- Item (inside a Sample or a BlockItem): what attention is on, or what runs in the background (2.3).
- Block (the block log, one file per date, permanent; the open block in `current.json`, 4.4): a stretch of attention.
  - A foreground block has foreground items; a background block has only background items and lies between foreground blocks.
  - The end reason `split` means the work changed (for a background block, that attention came back), `maxLength` that the block reached its longest length, and `stopped` that the agent stopped running; the other reasons are the states that ended it. It is absent while the block is open.
  - The value `reconstructedSeconds` is the part of the credited time that came from `appUsage` Samples.
  - Totals (active time, time per device, the dominant workspace and its share) are not stored: library functions compute them from the items on read.
- BlockItem (inside a Block): an Item with the name of the device it ran on and the seconds it earned. Equal Items on one device add up.
- DeviceEvent (CloudKit, written by the iPhone and iPad): one event of an iOS collector (6.2). Its `utcOffset` places it on the device's local date, its `kind` and `payload` depend on the source ([ios.md](ios.md) §9.1), and its `sequence` orders events of the same time and makes the record name unique. The Mac keeps the fetched events in `samples.sqlite` as long as Samples, and the remote activity loop turns a device-date's events into Samples.
- DeletedRange (`meta` in `samples.sqlite`, 90 days): time the user deleted (2.6). No Sample inside it is ever stored again, so a late iPhone event, a synced visit, or app usage read again can't bring the time back.

### 2.3 Items

An Item's attributes, from coarse to fine:

- `app`: the app in front, or the tool of a background item (`Claude Code`, `tmux`). For a Screen Time set, the set's label; for the set "Everything", the device's name. Example: `WezTerm`.
- `appID`: the bundle identifier; for an iOS source without one, the source (`screenTime`, `intent`), and `screenTime.everything` for the Screen Time set "Everything", so it ranks below the named sets (2.7) whatever the device is called. Example: `com.github.wez.wezterm`.
- `window`: the window or tab title. Example: `Fix parser #123`.
- `host`: the machine the work runs on, when it is not the Sample's device; absent otherwise. Example: `hpc`.
- `session`: the innermost named session of the chain a terminal can hold (local tmux, ssh, remote tmux, a coding agent): the agent's session title, else tmux's `session:window.pane`, else a chat app's workspace. Example: `refactor-parser`.
- `location`: where the work is, as a full path or a full URL. Example: `~/Code/MyApp/src`.
- `documents`: the files the user works on, open in an editor or viewer. Example: `~/Papers/2026_Noise/notes.tex`.
- `command`: the full command line of the frontmost process, as in the shell history. Example: `nvim notes.tex`.
- `workspace`: the project the work belongs to, which decides where blocks split and names them in the summary (2.8). It is stored as a full path or name and shown as its last component (`MyApp`). The first rule that applies gives it:
  1. With a `host`: `<host>:<location>`, and `<host>:` while the remote shell reports no folder.
  2. A path: the nearest enclosing folder holding one of the `root_markers` (`.git`, `Project.toml`, `pyproject.toml`, `Package.swift`, and others, 7.1), with a git worktree resolved to its main repository; without one, the path's folder. The home folder is never a workspace: a path that would give it falls through to rule 5.
  3. A `localhost` URL: the workspace of the working folder of the process listening on its port, so a notebook in the browser belongs with the terminal that runs its server.
  4. Any other URL: the first pattern in `[workspaces] urls` that matches; its capture group names the workspace, so `github\.com/([^/]+/[^/]+)` gives `owner/MyApp`. When a repository among the Samples' workspaces has an `origin` remote with that name, the workspace is the repository's folder instead, so a pull request page joins the code it changes.
  5. Anything else: the app.

So a PDF in Skim, Neovim in a terminal, and the project's pull request in Safari share one workspace, and switching between them never splits a block.

Over ssh, the Mac sees only what the terminal reports. OSC 7 from the remote shell gives the host and folder, and a remote tmux with `set-titles` passes its session and command; the Tracker pane offers snippets for both (7.4). Collectors running on Linux hosts are planned; they will add Samples of their own.

Items by source, with synthetic values. The device in parentheses is the Sample's, by name; a Mac app's appID, its bundle identifier, is left out.

- tmux pane with Neovim (MacBook): app `WezTerm`, window `Research`, session `paper:draft.1`, location `~/Papers/2026_Noise`, documents `~/Papers/2026_Noise/notes.tex`, command `nvim notes.tex`, workspace `~/Papers/2026_Noise`.
- Plain shell without tmux (MacBook): app `WezTerm`, window `Research`, location `~/Code/MyApp/src`, command `zsh`, workspace `~/Code/MyApp`.
- Claude Code in focus (MacBook): app `WezTerm`, window `Research`, session `refactor-parser`, location `~/Code/MyApp`, command `claude --resume`, workspace `~/Code/MyApp`.
- Claude Code in the background (MacBook): app `Claude Code`, appID `claude`, session `refactor-parser`, location `~/Code/MyApp`, command `claude --resume`, workspace `~/Code/MyApp`.
- Build in another pane, in the background (MacBook): app `tmux`, appID `tmux`, session `paper:build.0`, location `~/Code/MyApp`, command `make test`, workspace `~/Code/MyApp`.
- ssh to a host (MacBook): app `WezTerm`, window `hpc`, host `hpc`, session `job:1.0`, location `/scratch/run7`, command `ssh hpc`, workspace `hpc:/scratch/run7`.
- Job on a host, from a planned host collector (MacBook): app `tmux`, host `hpc`, session `job:2.0`, location `/scratch/run7`, command `julia --project run.jl`, workspace `hpc:/scratch/run7`.
- Web page (MacBook): app `Safari`, window `Fix parser #123`, location `https://github.com/owner/MyApp/pull/123?w=1`, workspace `~/Code/MyApp`.
- Notebook on localhost (MacBook): app `Safari`, window `notes.ipynb`, location `http://localhost:8888/lab`, workspace `~/Papers/2026_Noise`.
- Private window (MacBook): app `Safari`, location `(private)`, workspace `Safari`.
- Document in Skim (MacBook): app `Skim`, window `notes.pdf`, location `~/Papers/2026_Noise`, documents `~/Papers/2026_Noise/notes.pdf`, workspace `~/Papers/2026_Noise`.
- Finder (MacBook): app `Finder`, window `2026_Noise`, location `~/Papers/2026_Noise`, workspace `~/Papers/2026_Noise`.
- Chat app (MacBook): app `Slack`, window `general`, session `Acme`, workspace `Slack`.
- Any other app (MacBook): app `Mail`, window `Inbox`, workspace `Mail`.
- App usage history (MacBook): app `Mail`, workspace `Mail`.
- Synced Safari history (`remote`): app `Safari`, appID `com.apple.Safari`, location `https://arxiv.org/abs/2401.1`, workspace `arxiv.org`.
- iOS Safari web extension (iPhone): app `Safari`, appID `com.apple.mobilesafari`, location `https://arxiv.org/abs/2401.1`, workspace `arxiv.org`.
- iOS Screen Time set (iPhone): app `Social`, appID `screenTime`, workspace `Social`.
- iOS Screen Time "Everything" (iPhone): app `iPhone`, appID `screenTime.everything`, workspace `iPhone`.
- iOS Shortcuts automation (iPad): app `Goodnotes`, appID `intent`, workspace `Goodnotes`.

(tracking-local)=
### 2.4 Local activity loop

Each pass of the local activity loop, a *tick*, takes a live Sample of the Mac: every 30 seconds, and at once on lock, sleep, wake, a user switch, an app switch, and a `tracker-event` message (3.1). Section 3 says how each source fills the Sample. Each tick also rewrites the foreground, presence, and health in `current.json` (4.4).

Every 15 minutes, the loop fills in the time the agent didn't run. It looks back to where it last read, and at least 24 hours, because macOS writes app usage late, but never before `fill_after`: the time of the agent's first start, or of its first start after the tracker was disabled, so time the tracker was meant to be off stays empty. The Mac app marks a disable with the file `disabled` in the agent folder: when the user clicks "Disable Tracker" (7.4), and when its status check finds the login item off. At start, the agent that finds the file sets `fill_after` and removes it. Every stretch in that time longer than `idle_close` (5 min) without a live Sample is a gap. In each gap it replaces the `appUsage` Samples with one Sample every 30 seconds through each app interval that `knowledgeC.db`, the macOS app usage history (3.2), has there.

Once a day it moves the cutoff date forward by at most one day, toward today − 90 days but never before the date of the agent's first start, and deletes the Samples and deleted ranges before it; so a clock that jumps ahead can't delete everything at once. It first waits until no date before the new cutoff is in `changed_dates` or waiting for an iCloud Drive download, and no device-date before it is waiting for a redo, so a pending change reaches its file before the date freezes. That marks no date, because those dates are now frozen (4.1).

- Reads: macOS state; `knowledgeC.db`; the file `disabled`; from `samples.sqlite`, the times of live Samples (to find the gaps), how far app usage was read, and `fill_after`.
- Writes: inserts each live Sample; replaces the `appUsage` Samples of each gap; deletes old Samples and deleted ranges and moves the cutoff date; the foreground, presence, and health in `current.json`.

(tracking-remote)=
### 2.5 Remote activity loop

Every 5 minutes, the remote activity loop fetches the DeviceEvents added to CloudKit since its last fetch and stores them in `samples.sqlite`, together with the new CloudKit token and the device-dates they touch. For each such device and device-date, it takes that date's stored events, with the device's last stored events before it and its first after it, converts them into Samples (6.2), and replaces the device's iOS Samples of that date. A device-date runs from its 00:00 to the next date's 00:00, each at the UTC offset of the device's last event before that midnight, so adjacent dates meet even on the night daylight saving time ends. It redoes a whole date because how long an event lasts depends on the events after it, which can arrive in a later fetch. The last events before the date tell what was still on at 00:00 (an app in front, a Focus, an app an automation opened), so such time continues into the date, and the first events after it tell when what is on at the date's end stops. A date with new events also redoes the date before it, which a late close can lengthen, and when a redo changes what is on at a date's end, the loop redoes the next date too. A record this version of the app can't read is skipped, and the token moves past it, so it can't stall the feed (3.5). It deletes DeviceEvents before the cutoff date, stored and in CloudKit, except each device's and source's last one before it, and also the CloudKit records before it that it can't read. Keeping the events on the Mac makes a redo local: it needs no network and no CloudKit query, only the change feed.

Then it reads the visits that Safari synced into `History.db` from other devices over the last 24 hours and replaces the `safariHistory` Samples of that time (6.1).

- Reads: CloudKit's change feed; `History.db` and `CloudTabs.db`; from `samples.sqlite`, the stored DeviceEvents, the CloudKit token, and the pending device-dates.
- Writes: stores new DeviceEvents with the token and the pending device-dates; replaces the Samples of each pending device-date; replaces the `safariHistory` Samples of the last 24 hours; deletes old DeviceEvents.

(tracking-requests)=
### 2.6 Request handler

The request handler runs a request when it arrives, between two passes of the loops. Requests come through the agent's socket (7.3). Delete This Activity… in the Calendar deletes the Samples of a time range, adds the range to the deleted ranges, ending at the latest at the time of the request so recording goes on, and marks its dates; for the part of the range on frozen dates, it removes the blocks from the date files instead. The command `tracker-event forget-day` deletes a whole date the same way. The command `tracker-event reapply-exclusions`, sent after editing the exclusions, applies them to the Samples of the given dates, updating or deleting each and marking the dates that changed, and to the items in the frozen date files of those dates.

- Reads: the Samples to re-filter; the cutoff date; the block log, for frozen dates.
- Writes: deletes Samples and adds a deleted range, or re-filters Samples; edits frozen date files.

(tracking-rebuild)=
### 2.7 Rebuild loop

The rebuild loop turns Samples into blocks. It runs while `changed_dates` is not empty. Each pass takes one date D out of the set, the oldest first, with today only when no other date is left. A frozen D is skipped and its file stays as it is. Otherwise the pass forms the blocks that start on D from the Samples alone; the only thing it reads from an earlier pass is where D−1's last block ends, foreground or background, which `meta` keeps.

The walk runs through time without Samples up to now: the Mac takes a Sample every 30 seconds while it is awake, so time before now without a Sample is empty, and a late Sample marks its dates again anyway. A pass can end before its walk stops (step 3), because the walk reached now and no Sample has come yet that settles D's last block. Then D is *unsettled*, and D+1's pass forms nothing, leaves D+1's file as it is, and puts D back into `changed_dates`, so D runs again first. Since every Sample before D+1 00:00 plus `max_passive_block` (3 h) also marks D (4.1), D's pass runs again with each new Sample, including a late one, until D settles. A walk that reaches the end of the time it reads (step 1) settles D there. So a Mac asleep from 23:00 to 08:00 settles the evening's date when the morning's first pass of the next date runs. `meta` keeps, for every date from the cutoff date on, where its last block ends, or that it is unsettled.

A Sample with the state `locked`, `asleep`, `otherUser`, or `paused` ends the open block at once, unless an attentive Sample of another device follows within `idle_close` (5 min): then it counts as `idle`, so the block runs on from the Mac to the iPhone. A block that a lock ends therefore reaches its date file `idle_close` after the lock, once no other device took over; until then `current.json` shows it as open. The state `idle` doesn't end a block, but a block closes after `idle_close` (5 min) without an attentive Sample. A block's length is its span from start to end, gaps included. A pass has four steps:

1. Read the Samples of D: from where D−1's last block ends (at the earliest D 00:00) to D+1 00:00 plus `max_passive_block` (3 h), so a block that starts on D can run past midnight.
2. Pick the foreground. Each Sample covers the time up to the next Sample of its *series*, at most 60 seconds: the same device and source, and for Screen Time the same set, for automations the same app (the Item's app tells both), so a named set and "Everything" on one iPhone don't cut each other short. A Sample with a foreground Item claims the time it covers. Where several Samples claim the same time, one of them wins it.
   - The sources rank: the Mac (`live`, `appUsage`), the TimeTracking app, automations, Safari tabs, Screen Time sets the user named, Screen Time "Everything", synced Safari visits. On a tie, the later Sample wins.
   - The winner credits its foreground Item for that time. A losing Sample of the winner's device credits nothing there, because its use is already counted (as "Everything" is behind a named set). A losing Sample of another device moves its foreground Item to its background Items, still on its own device.
   - In time an attentive Sample claims, a Sample without a foreground Item (states `idle`, `locked`, `asleep`, `otherUser`, and `paused`, or an app in `exclude_apps`) neither ends nor idles the block; only its background Items count. So when the user locks the Mac and reads on the iPhone, the block runs on from the Mac to the iPhone and back.
3. Form blocks.
   - Foreground blocks. The pass walks through the Samples in time order.
     - An attentive Sample opens a block if none is open, and credits the time it won to the open block, under its device and foreground Item; equal Items on one device add up. Time from `appUsage` Samples also counts toward `reconstructedSeconds`. An open block ends where its credited time ends.
     - A Sample whose state ends a block closes the open block, with that state as the end reason. After `idle_close` (5 min) without credited time, the block closes where its credited time ends, with the reason `idle`, or `stopped` when its last credited Sample was the Mac's and the Mac took no Sample at all since (the agent wasn't running).
     - Once the open block is longer than `split_after` (20 min), it is checked for a change of work after every Sample. A change point is a time where the credited time moves to another workspace, with at least `min_half` (10 min) of credited time on each side. Its distance compares each workspace's share of the credited time before (L) and after (R): 1 − Σ min(L, R) / Σ max(L, R), so 0 means the same mix and 1 means no workspace in common. If the largest distance (the earliest point, on a tie) reaches `split_threshold` (0.7), the part before the point closes with the reason `split`, the rest stays open, and the check repeats. So moving from one workspace to another splits at the move, while alternating between two never does, because both sides hold the same mix.
     - When the open block reaches `max_block` (90 min), or `max_passive_block` (3 h) if more than half its credited time is passive, it is cut at the change point (as defined above, with `min_half` on each side) with the largest distance among those in its last 30 minutes, whatever the distance, or closed right there if it has none. The reason is `maxLength`.
     - A closed block shorter than `min_block` (10 min) is held, not kept. Its window lasts `idle_close` (5 min) plus its own length after its end. If an attentive Sample comes within the window, the held block reopens and continues; the gap earns nothing. If the window passes, the held block merges into the previous block when the gap between them fits in the same window and the merged block fits in `max_block` (90 min); the previous block keeps its start. Otherwise the held block is dropped, as is a block with no credited time.
     - The walk stops at D+1 00:00, or later, once no foreground or background block is open or held and `idle_close` (5 min) plus `min_block` (10 min) have passed since D's last block ended. So a short block after midnight that merges into D's last block belongs to D. A block after midnight that doesn't merge ends the walk at its start; it and later blocks are left to D+1's pass.
   - Background Items. Each earns the time up to the next Sample of its series, at most 60 seconds, under that device.
     - Inside a foreground block's range, including its gaps, they go into its background list.
     - Outside, they form background blocks, which have no foreground items. A background block ends after `idle_close` (5 min) without a background Item (reason `idle`), at the next foreground block (reason `split`), or at `max_background_block` (3 h) (reason `maxLength`). Its items with less than `min_background_item` (5 min) are dropped, and with them the block if none are left; the block spans the time of the items it keeps.
4. Write the blocks of D. If they differ from D's file, the file is rewritten whole; an open or held block, foreground or background, is not written yet. If the end of D's last block moved, or D became settled, D+1 goes into `changed_dates`, because D+1's pass starts there. If the walk ended because it reached now, the foreground block it left open goes to `current.json`, or `null` when none is open (a held block counts as none).

- Reads: `changed_dates`; the Samples of D; where D−1's last block ends, or that D−1 is unsettled.
- Writes: D's file in the block log; the block in `current.json`; where D's last block ends, or that D is unsettled; removes D from `changed_dates` when it takes D, and adds D+1 when D's last block moved or D settled. A crash before D's file is written leaves D marked, and a Sample that marks D during the pass marks it again.

### 2.8 Block summary

The Calendar's activity column shows blocks, and hovering one shows its summary ([calendar.md](calendar.md) §3.2), computed from the one Block on read.

```{raw} html
:file: figures/activity_tracking_summary.svg
```

{.tt-caption}
Figure 3. Hovering the 09:52 block. Each workspace shows by name (the last component of its path), with the full path beside it, its share of the active time, and its items. Synthetic values.

- The header gives the block's start, end, and length, then the active time (the sum of its foreground seconds), why it ended, and the devices that contributed. Another device's name stands out, here the iPhone.
- Foreground items group by workspace, the largest first, each with its share of the active time. Within a group, items are ordered by time, and each is labeled with its app and the first it has of a document's name, the session, or the window. Items that read the same (one document in Skim, its window title naming each page) are one line with their seconds added, where the first of them was.
- Up to `summary_lines` (6) item lines show, and a workspace below `summary_min_share` (5%) of the active time folds into "+n more".
- Background items follow, the largest first and at most three, with their workspace, each labeled with its app and its command for a job (`job_commands`), else its session; those with the same label and workspace are one line.
- The footer says how much of the time was rebuilt from app usage history, and is absent when none was.
- The end reasons read: went idle, screen locked, Mac slept, user switched, Focus paused collection, moved on to other work, reached its longest length, tracker stopped.

## 3. Sources on the Mac

### 3.1 Terminal

The focused pane's tty comes from a terminal adapter: WezTerm through `wezterm cli`, iTerm2 and Terminal.app through AppleScript. Without one, it is the tty below the frontmost terminal with the most recent input. A tmux client on that tty gives the session, window, and pane, and the active pane's command and cwd; without tmux, the tty's foreground process and its cwd. The agent runs tmux with `-u`: under launchd it has no UTF-8 locale, and tmux would then write `_` for the tabs between the fields it reports. The cwd is the location, the foreground process's command line the command.

The pane's foreground program refines the Item:

- Editors add their file to `documents`. The file comes from the pane title matched against `title_patterns`, trusted only while the pane's command is that editor, then Neovim RPC (200 ms timeout), then process arguments. While the title works, RPC cross-checks it every 10 minutes per pane and reports a mismatch to health.
- Claude Code is recognized by a live session in `~/.claude/sessions/<pid>.json` within the pane's process tree, which gives the session title (the Item's session), cwd, tmux target, and busy or idle status; transcripts are never read.
- Interpreters (Julia, Python, R, Node) and other programs give their command line. A notebook server's listening port links a browser tab on it to this workspace (2.3).
- An ssh session gives the host and folder through OSC 7 from the remote shell, and the remote tmux session and command through its window title with `set-titles` (2.3).

A Sample's background Items, taken also while the user is away but not while the Mac sleeps, are every busy coding agent session, every tmux client with input in the last 30 seconds in a session other than the foreground Item's, and every pane running one of `job_commands` other than the foreground Item's pane.

The tmux hooks `client-session-changed`, `after-select-window`, `after-select-pane`, and `client-focus-in` (which needs `set -g focus-events on`), and the Claude Code hooks `UserPromptSubmit`, `Stop`, and `SessionEnd`, may call `tracker-event tmux <hook>` and `tracker-event agent <hook>`, which write one line to the agent's socket and take a Sample. The hook's name is required. The snippets of 7.4 run the tool in the background and discard its output and exit status, so neither a stopped tracker nor the Sample it waits for (over a second) holds up tmux or Claude Code, which cancels `SessionEnd` hooks after 1.5 seconds. The sources `tmux_events` and `agent_events` are `active` when such an event arrived in the last 7 days, and `remote_shell` when an OSC 7 report with a host did.

### 3.2 App usage history

The macOS Knowledge store (`knowledgeC.db`, Full Disk Access) records app intervals. The agent reads a copy, and sets the source `knowledge` to `off` when the schema is not the expected one. The local activity loop builds `appUsage` Samples from it for the gaps in the live Samples (2.4); such a Sample has an Item with app and appID only, and the state `active`.

### 3.3 Browsers

The active tab of a frontmost browser is read through Apple Events: Safari's current tab, and for Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi) the active tab, skipping incognito windows. Browsers without a scripting dictionary, or with Automation denied, give `AXURL` plus title, and "Private Browsing" in the title marks a private window. The tab's title is the window, its URL the location.

Safari private windows write no history, so a sampled Safari URL with no visit in the last 24 hours in `History.db` is recorded as a private window, with the location `(private)` and no window, until its visit shows up. Without Full Disk Access, Safari URLs are reduced to the domain.

Histories are read from copies, never the live files; a copy during which the database or its WAL changed is made again, up to three times.

### 3.4 Presence

Idle seconds, lock, display sleep, system sleep, and user switches come from system events that need no permission; console ownership is checked each tick. The first that applies gives a Sample's state:

1. `asleep` while the Mac sleeps, `otherUser` while another user owns the console, `locked` while the screen is locked.
2. `passive` while an app in `passive_apps` or a tab on `passive_domains` is frontmost with the display on, without input for `idle_after` (2 min), up to `passive_limit` (3 h) since the last input. Audio-only apps never count.
3. `idle` without input for `idle_after` (2 min), or with the display off.
4. Otherwise `active`.

A Sample that is not `active` or `passive` has no foreground Item.

### 3.5 Health and fallbacks

Each source reports `active`, `fallback`, or `off` (cannot run) in the health record (4.4), with a reason when not `active`. A source the settings file turns off, such as `synced_safari` by default, is not listed: it is not a problem. Screens show the status as "On", "Limited", or "Off", the source by its name on screen, and the reason as written: a consequence for the user, never a mechanism. Mechanisms go to the log.

| Id | Name on screen | Fallback, with its reason |
|---|---|---|
| `window` | Window titles | App name only ("Accessibility is off; only app names are recorded") |
| `terminal` | Terminal tab | Process tree plus last input ("`<App>` can't report its front tab; the tab is guessed from recent activity") |
| `tmux` | tmux sessions | The tty's foreground process and cwd ("tmux is not running") |
| `editor` | File open in Neovim | Editor RPC, then process arguments, then none |
| `agents` | Coding agents | Process plus cwd, busy state unknown ("Claude Code not found; when it is working can't be told") |
| `tmux_events` | tmux hooks | The tick alone ("No tmux hook event in the last 7 days; switches are noticed up to 30 seconds late") |
| `agent_events` | Claude Code hooks | The tick alone ("No Claude Code hook event in the last 7 days; changes are noticed up to 30 seconds late") |
| `remote_shell` | Remote shells | The ssh command only ("No remote shell reported its folder in the last 7 days; work over ssh is recorded by host only") |
| `browser` | Browser tab | `AXURL` plus title ("`<App>` can't report its tab; the address is read from the window", "Automation is off for `<App>`; the address is read from the window") |
| `history` | Browser history | Sampled tabs only ("Full Disk Access is off; Safari pages are recorded by site only") |
| `knowledge` | App usage history | Off ("macOS app usage history was not found", "Full Disk Access is off; macOS app usage history can't be read", "macOS changed how it stores app usage; this version can't read it") |
| `shared_folder` | iCloud Drive | `fallback` "Copied to iCloud Drive while the app is open"; `off` "iCloud Drive is off; activity stays on this Mac", "Another Mac records activity; choose Record on This Mac to record here" (4.1) |
| `device_events` | iPhone and iPad | `fallback` "Checking…" until the first fetch, "Couldn't reach iCloud; trying again in 5 minutes" after a failed one, "Some iPhone or iPad activity comes from another version of the app; update the app on every device" after a fetch that skipped records it can't read; `off` "iCloud is not available; iPhone and iPad activity doesn't reach this Mac" |
| `synced_safari` | Safari on other devices | Off, while turned on in the settings file ("Full Disk Access is off; Safari on other devices can't be read") |

## 4. Storage

(tracking-store)=
### 4.1 Files and folders

The agent folder is `<App Group container>/Library/Application Support/TimeTracking/`. Nothing in it leaves the Mac. It holds:

- `samples.sqlite`: a table of Samples (time, device, source, state, and the Items as JSON), a table of the DeviceEvents fetched from CloudKit (2.5), and a `meta` table of keys: the CloudKit token, how far app usage was read, `fill_after` and the date of the agent's first start (2.4), the cutoff date, the deleted ranges, `changed_dates`, for each date from the cutoff date on, its UTC offset (below) and where its last block ends (2.7), the device-dates the remote activity loop still has to redo, kept with the CloudKit token so a crash loses no events, the latest name of each iOS device, the dates waiting for an iCloud Drive download (below), and the text of the last `settings.toml` read (7). Samples, DeviceEvents, and deleted ranges are kept 90 days.
- `Activity/current.json`: the open block and the tracker's state (4.4).
- The socket `tracker.sock` (7.3), and `agent.lock`, which the running agent holds, so a second agent exits, as does one that can't open the lock file.
- `disabled`, while the tracker is disabled (2.4).

Every part writes Samples through two operations on the Sample table, so no write skips the deleted ranges or forgets to mark a date:

- `insert` takes a list of Samples, stores the ones outside every deleted range and on no frozen date, and adds their local dates to `changed_dates`, and the previous date for a Sample before 00:00 plus `max_passive_block` (3 h), since that date's pass reads it too (2.7).
- `replace` takes a selection of stored Samples, such as "the iPhone's Samples of D from an iOS source", and a list of new Samples. If they differ, it deletes the selection, marks its dates, and inserts the new list; if they are equal, it changes nothing.

The shared folder is `Activity/` in the product's iCloud Drive container, outside `Documents/`. It holds the block log, `blocks/YYYY-MM-DD.jsonl` with one file per local date, kept permanently, and `settings.toml` (7.1). A date's 00:00 is fixed the first time a Sample marks the date, at the UTC offset then in effect, so after travel every pass uses the same boundaries as the passes before it.

One Mac records: the file `blocks/owner` holds the hardware UUID of the Mac whose agent writes the date files. "Enable Tracker" and "Record on This Mac" in the Tracker pane (7.4) write it, so the Mac enabled last takes over; without the file, the first agent to write a date file claims it. An agent on another Mac keeps taking Samples but writes no date file, and reports `shared_folder` as `off`.

A block goes in the file of the date it starts and may run past 00:00; the longest blocks (`max_passive_block`, 3 h) bound how far. Readers count a block whole on the date it starts.

A date before the cutoff date (today − 90 days, but never before the agent's first start, 2.4) is frozen: the rebuild loop never reads it, because its Samples are gone and rebuilding it would empty its file. Only the request handler (2.6) edits a frozen file, in place.

Every write of a date file or `current.json` replaces the whole file, so a reader sees a date before or after a rebuild, never in between. A date file that iCloud Drive holds only as a placeholder is never written: the agent asks for its download and keeps the date in `meta`; a tick that finds the file arrived puts the date back into `changed_dates`.

Without iCloud Drive, the agent folder's `Activity/` takes the shared folder's place (`shared_folder` reports `off`). When the container exists but cannot be written, the agent uses that folder too and `shared_folder` reports `fallback`, which alone tells the Mac app to copy each changed date file into the container and keep the two `settings.toml` identical (newer modification time wins).

(tracking-format)=
### 4.2 Block log format

A date file is JSON Lines, UTF-8. The first line is a header with the format number, 1, and the key legend, for a person reading the file; readers skip it like any line without `s`. Every other line is one Block, in the order of `s`. Keys are short, and a key whose value is empty, absent, or 0 is omitted. Readers skip lines and keys they don't know, take a BlockItem without `ws` as if its workspace were its app, and any other missing key as empty.

- Block
  - `s`: start, local time with its UTC offset. Identifies the block; its date names the file.
  - `e`: end, in the same form.
  - `r`: endReason.
  - `rc`: reconstructedSeconds.
  - `f`: foreground, a list of BlockItems; omitted for a background block.
  - `b`: background, a list of BlockItems.
- BlockItem: `d` (device, the device's name), `t` (seconds, whole), and the keys of its Item.
- Item: `a` (app), `i` (appID), `w` (window), `h` (host), `ss` (session), `l` (location), `dc` (documents, a list of paths), `c` (command), `ws` (workspace).

The first lines of a date file, with a foreground block, the 09:52 block of Figure 3 (shortened to two items), and a background block:

```json
{"format":1,"keys":{"s":"start","e":"end","r":"endReason","rc":"reconstructedSeconds","f":"foreground","b":"background","d":"device","t":"seconds","a":"app","i":"appID","w":"window","h":"host","ss":"session","l":"location","dc":"documents","c":"command","ws":"workspace"}}
{"s":"2026-11-07T09:10:00-05:00","e":"2026-11-07T09:44:00-05:00","r":"idle","f":[{"d":"MacBook","t":2010,"a":"WezTerm","i":"com.github.wez.wezterm","w":"Research","ss":"paper:draft.1","l":"~/Papers/2026_Noise","dc":["~/Papers/2026_Noise/notes.tex"],"c":"nvim notes.tex","ws":"~/Papers/2026_Noise"}]}
{"s":"2026-11-07T09:52:00-05:00","e":"2026-11-07T11:05:00-05:00","r":"idle","rc":240,"f":[{"d":"MacBook","t":1440,"a":"WezTerm","i":"com.github.wez.wezterm","w":"Research","ss":"refactor-parser","l":"~/Code/MyApp","c":"claude --resume","ws":"~/Code/MyApp"},{"d":"iPhone","t":720,"a":"Social","i":"screenTime","ws":"Social"}],"b":[{"d":"MacBook","t":2280,"a":"Claude Code","i":"claude","ss":"refactor-parser","l":"~/Code/MyApp","c":"claude --resume","ws":"~/Code/MyApp"}]}
{"s":"2026-11-07T11:15:00-05:00","e":"2026-11-07T11:58:00-05:00","r":"idle","b":[{"d":"MacBook","t":2580,"a":"tmux","i":"tmux","ss":"paper:build.0","l":"~/Code/MyApp","c":"make test","ws":"~/Code/MyApp"}]}
```

### 4.3 Redaction

The Samples keep full command lines and URLs. Writing the block log and `current.json`, the agent runs redaction filters over windows, locations, and commands: each filter replaces only the part of a value it recognizes as a secret with `(private)`, and the rest of the value stays. The default filters match the value after an option in `redact_options` (such as `--password` and `--token`); `NAME=value` where the name contains an entry of `redact_names` (TOKEN, SECRET, PASSWORD, KEY); `Authorization:` headers and user info in URLs (`redact_patterns`); the values of query keys in `redact_query_keys` (such as `token`, `key`, `sig`, and `code`); and the whole query on the search sites of `redact_query_sites`. All of them are settings in `[privacy]` (7.1).

(tracking-current)=
### 4.4 Current state

The local activity loop rewrites `current.json` on every tick with the foreground, presence, and health, and the rebuild loop whenever the open block changes (2.7), so liveness never waits for a rebuild. It is never copied to the shared folder.

```json
{"format":1,"block":{"s":"2026-11-07T09:52:00-05:00","e":"2026-11-07T10:10:30-05:00","f":[{"d":"MacBook","t":1080,"a":"WezTerm","i":"com.github.wez.wezterm","ss":"refactor-parser","l":"~/Code/MyApp","c":"claude --resume","ws":"~/Code/MyApp"}]},"foreground":{"a":"WezTerm","i":"com.github.wez.wezterm","ss":"refactor-parser","l":"~/Code/MyApp","c":"claude --resume","ws":"~/Code/MyApp"},"presence":{"state":"active","since":"2026-11-07T09:52:00-05:00","last_input":"2026-11-07T10:10:27-05:00"},"health":{"last_tick":"2026-11-07T10:10:30-05:00","version":"1.0 (42)","sources":[{"id":"terminal","name":"Terminal tab","status":"active","reason":""}]}}
```

The `block` is the open block, which may have started yesterday, with the keys of 4.2, `e` the end of its credited time so far and without `r`, or `null`. The `foreground` is the latest live Sample's foreground Item, `null` while the user is not attentive. In `presence`, `state` is the latest live Sample's, and `since` is the time of the event or input that set it, not of the tick that noticed it. The list `health.sources` holds every source of 3.5 that the settings file doesn't turn off.

Every reader derives the tracker's liveness from `health.last_tick` by one rule: the tracker is running while the last tick is younger than 2 minutes, and not running when it is 2 minutes old or older or `current.json` is missing. While running, a last tick of 90 seconds or older counts as delayed. The Tracker pane, the Activity footer, the menu bar warning, the Timer's idle detection, and `agentRunning` in `LiveState` all use this rule.

The Timer reads `presence` for its own idle detection ([timer.md](timer.md)). The Mac app copies the tracker fields into `LiveState` ([data_and_sync.md](data_and_sync.md) §4.1); they are already filtered by the exclusions and redacted.

## 5. Agent

The agent, `TimeTrackingAgent.app`, is a headless login item with `KeepAlive` ([architecture.md](architecture.md)), always team-signed because TCC keys grants to signing identities. Its loops and request handler run one step at a time (Figure 1), and tick requests arriving during a step share one tick after it. A rebuild backlog never delays a tick, because a tick that is due runs between two steps of a rebuild pass. A command the agent runs (`ps`, `tmux`, `lsof`) that is still running after 5 seconds is stopped and counts as unreadable, so a hung one cannot stall the loops. On SIGTERM (logout, shutdown, unregistration) it finishes the running step, for at most 5 seconds, answers waiting requests `error the tracker is stopping`, and exits; a step cut short loses nothing, because every write replaces a whole file or commits a whole transaction. The next start fills the gap from app usage (2.4).

The flag `--record <folder>` writes adapter outputs and Samples as fixtures, with home-directory paths, host names, and URL paths replaced by placeholders. The flag `--replay <fixture>` runs the rebuild loop over a fixture's Samples as if all of its time had passed, compares the date files with the fixture's expected ones, and exits non-zero on a difference. The flag `--unregister` writes the file `disabled` (2.4), removes the login item registration, and exits.

| Permission | Granted to | Gives |
|---|---|---|
| Accessibility (required) | `TimeTrackingAgent.app` | Window titles, documents, browser addresses |
| Automation, per browser and scriptable terminal | The app | The browser's tab and the terminal's front tab; macOS asks at first use, or on "Ask for Access" (7.4) |
| Full Disk Access (optional) | The app | The Knowledge store, Safari's history and synced tabs |

macOS checks Accessibility for the agent itself, but attributes the agent's file access and Apple Events to its responsible app (`AssociatedBundleIdentifiers`, [architecture.md](architecture.md) §1.4). The app therefore carries the Apple Events entitlement and `NSAppleEventsUsageDescription` as well as the agent; without them macOS refuses the Apple Events with `-1743` and never asks. A new Full Disk Access grant reaches the running agent only after a restart.

## 6. Other Apple devices

### 6.1 Synced Safari history

With `synced_safari_history` (off) on, the remote activity loop stores the visits that Safari synced from other devices (`History.db` visits with `origin = 1`) as `safariHistory` Samples. It is off by default: attribution is weak, and it duplicates the iOS web extension, which outranks it (2.7). Such visits can arrive hours late, so each read covers the last 24 hours again. A visit lasts until the next visit if that comes within 5 minutes, else 1 minute. A run of visits belongs to the device whose open tabs in `CloudTabs.db` gained one of its URLs during the run, or to `remote` if none or several did.

### 6.2 Collected by the iOS app

The iPhone and iPad take no Samples and run no loop. Their TimeTracking app and its extensions record events, each with a time and a label, apply the exclusions, and upload them as DeviceEvents ([ios.md](ios.md) §9). Collection is off by default and set up per device in the app, under Settings, Activity collection. Each source works without the others. The remote activity loop turns the time each event counts into one Sample every 30 seconds, on the device's `deviceID`, with the state `active` (`paused` for a Focus that pauses collection):

- Screen Time (`screenTime`). iOS doesn't let an app read how long other apps were used. It only lets a monitor extension ask to be woken when today's use of a set of apps reaches a threshold. TimeTracking registers a series of thresholds, so each wake-up says "set Social reached 37 minutes at 10:52", and the minutes since the previous threshold are placed just before 10:52. The Samples get the set's label as app and workspace and `screenTime` as appID. The user picks a set's apps with Apple's picker, and the app gets only an opaque token for them, never their names, so a set is known by the label the user gives it. The set "Everything" covers all use of the device and is created automatically; its Samples have the device's name as app and workspace, and the appID `screenTime.everything`.
- Safari (`webext`). A Safari web extension sends the domain and path of the front tab when it changes. A tab counts until the next one, at most 1 minute, as a browser Item.
- Automations (`intent`). A Shortcuts personal automation can run the app's action "Log Activity Event" with a name and a kind, such as when an app opens and closes. An app opening counts until its closing, if that follows within `max_block` (90 min); any other event counts 1 minute. The name is the app and workspace.
- The app's own time (`app`). TimeTracking records when it comes to the front and goes to the background, and counts the time between, at most `max_block` (90 min).
- Focus (`focus`). A Focus with the app's filter "Log Activity" and "Record Safari Sites and Automations" off pauses those two sources while it is on, and its time gets `paused` Samples, which end a block unless an attentive Sample, such as the Mac's or the device's own Screen Time, claims that time (2.7).

## 7. Settings and exclusions

All settings live in `settings.toml` in the shared folder, read by the agent and the iOS collection. A file that cannot be read (a parse error, an iCloud Drive placeholder, or a missing file that was read before) leaves the settings last read in force, exclusions included, until it can. The agent keeps the text of the last file it read in `meta`, so those settings survive a restart; a file missing on a new Mac is most likely not yet listed by iCloud Drive, and the defaults would record excluded apps. The file is the user's to edit. The app writes it only to create the default file when there is none, and to add an exclusion drafted in the Activity section, which inserts one value and keeps every other byte. The agent applies a change from the next tick.

### 7.1 Defaults

The default file holds these values, with a comment on every setting. A missing key takes its default, and a key the tracker doesn't know is ignored. Durations read `"30s"`, `"5m"`, `"3h"`; `~` in a path is the home folder; domains match themselves and their subdomains; apps are named by bundle identifier; patterns are regular expressions. The setting `idle_after` governs Samples only; the Timer's idle prompt has its own threshold. Fixed values: a live Sample every 30 seconds, at most 60 seconds per Sample, Samples kept 90 days, and late data read again 24 hours back.

```toml
[presence]
# A Sample without input for this long is idle, unless something passive is in front.
idle_after = "2m"
# Apps and sites that count as attention without input while in front.
passive_apps = [
    "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
    "com.apple.ScreenSharing", "com.apple.QuickTimePlayerX",
]
passive_domains = ["youtube.com", "netflix.com", "meet.google.com"]
# How long something passive counts as attention without input.
passive_limit = "3h"

[blocks]
# A block closes after this long without an attentive Sample.
idle_close = "5m"
# A shorter block is held, then merged into the previous one or dropped.
min_block = "10m"
# The split test runs once the open block is longer than this.
split_after = "20m"
# Credited time a change point needs on each side.
min_half = "10m"
# The distance at which a change point splits the block.
split_threshold = 0.7
# The longest block.
max_block = "90m"
# The longest block that is mostly passive.
max_passive_block = "3h"
# The longest background block.
max_background_block = "3h"
# A background block keeps only items with at least this much time.
min_background_item = "5m"
# Item lines in a block's summary, and the share below which a workspace folds.
summary_lines = 6
summary_min_share = 0.05

[workspaces]
# Files or folders that mark a project's folder.
root_markers = [
    ".git", ".hg", ".jj", "Project.toml", "pyproject.toml",
    "Package.swift", "Cargo.toml", "package.json",
]
# URL patterns, the first match wins; the capture group names the workspace.
urls = [
    'github\.com/([^/]+/[^/]+)',
    'gitlab\.com/([^/]+/[^/]+)',
    '^https?://(?:www\.)?([^/:?#]+)',
]

[terminal]
# Pane titles that name the editor's file.
title_patterns = { nvim = '^nvim (/.+)$' }
# Programs whose panes are background items while they run.
job_commands = ["make", "gmake", "latexmk", "pytest", "cargo", "swift", "npm"]

[devices]
# Visits Safari synced from other devices become Samples (6.1).
synced_safari_history = false

[privacy]
private_agent_paths = ["~"]
name_only_apps = ["com.1password.1password"]
# The other exclusion lists of 7.2 are empty.
# Redaction filters (4.3).
redact_options = ["--password", "--token", "--secret", "--api-key"]
redact_names = ["TOKEN", "SECRET", "PASSWORD", "KEY"]
redact_patterns = ['(?i)authorization:\s*(.+)', '://([^/@\s]+)@']
redact_query_keys = ["token", "key", "sig", "code", "access_token", "password"]
redact_query_sites = ["google.com", "duckduckgo.com", "kagi.com", "bing.com"]
```

A pattern in `redact_patterns` replaces its capture group, or its whole match without one.

### 7.2 Exclusions

Exclusions apply as a Sample is written: `insert` and `replace` (4.1) apply them, so every source on the Mac is covered (live Samples, app usage, synced Safari history, DeviceEvents), and the iOS web extension applies them before it records. They apply case-insensitively, to what is recorded from then on. Calendar and Activity also apply them to past activity when they show it ([activity.md](activity.md) §4); the Samples and date files keep what they hold until `reapply-exclusions` rewrites them (2.6). A path is checked wherever it appears (location, documents, a `file://` URL); an excluded file in an ordinary session hides the file and keeps the session. Two settings need what the tracker sees while it takes a Sample, because an Item doesn't keep it: afterwards (`reapply-exclusions`, Calendar, Activity), `exclude_tmux_sessions` matches only a session of the form `<name>:<window>.<pane>`, and `private_agent_paths` only Items whose app is `Claude Code`.

| Setting | Matches | Effect on the Item |
|---|---|---|
| `exclude_paths` | A path at or below an entry | Window, location, documents, and command `(private)`, workspace `private`; time kept |
| `exclude_keywords` | A path component starting with an entry | As `exclude_paths` |
| `exclude_tmux_sessions` | A tmux session name | Session `(private)`; window, location, documents, and command dropped; workspace `private` |
| `private_agent_paths` | A coding agent session's cwd, exactly | App, appID, and session only |
| `name_only_apps` | A bundle identifier | App and appID only |
| `exclude_apps` | A bundle identifier | No foreground Item; the Sample keeps its state, and its time earns no block |
| `private_domains` | A domain | Location reduced to the domain, window dropped |
| `exclude_domains` | A domain | As a private window (3.3) |
| `exclude_title_keywords` | A title substring | Window dropped |

(tracking-socket)=
### 7.3 Socket commands

The agent's socket takes one line of words (double quotes around a word with spaces), answered by `ok` or `error <reason>`. Dates are real local dates (`2026-11-07`), whatever the start of day is, and times carry their UTC offset, as in the block log (`2026-11-07T09:10:00-05:00`), so the hour repeated when daylight saving time ends is unambiguous. The commands `tmux <hook>` and `agent <hook>` make the local activity loop take a Sample (3.1); the others are requests for the request handler (2.6):

- `delete-block <s> <e>` deletes the time from `<s>` to `<e>`. "Delete This Activity…" in the Calendar sends a block's start and end, so a block the Calendar showed goes whole even when a rebuild has cut it since.
- `forget-day <date>` deletes the date.

On a Mac that doesn't record (4.1), `delete-block` and `forget-day` answer `error` with the `shared_folder` reason, because the blocks stay in the shared files, and `reapply-exclusions` applies only to its own Samples and leaves the date files alone. A `delete-block` that starts after now answers `error nothing at <s>`.
- `reapply-exclusions <from> <to>` applies the current exclusions to those dates' Samples and frozen date files, and drops a block left without items.

The user runs `forget-day` and `reapply-exclusions` with `tracker-event`. A rewrite keeps the lines of unaffected blocks byte-identical.

The reasons are protocol text; the Mac app logs them and shows its own sentence: "The tracker could not be reached.", "The tracker is not running." (nothing listens), "This activity is no longer in the logs." (`nothing at …`), "The tracker is restarting. Try again in a moment." (`the tracker is stopping`), and "The tracker could not change the logs." for any other.

### 7.4 The Tracker settings pane

The last pane of the Mac app's settings window ([timer.md](timer.md) §8). While visible it re-reads the status every 5 seconds. It has no editors for exclusions or options and no maintenance controls: the file is where settings are changed, and rewriting logs is a command-line task. From top to bottom:

Status. A dot and one line by the liveness rule of 4.4: green "Tracker running · checked 12 s ago", yellow "Tracker delayed · last checked 1 min ago", red "Tracker not running", gray "Tracker off" when the agent is not registered; then "Tracker version". One button by `SMAppService` status: "Enable Tracker" (`notRegistered`; it also makes this Mac the one that records, 4.1), "Open Login Items" (`requiresApproval`), "Disable Tracker" (`enabled`, after confirmation; it writes the file `disabled`, 2.4). Nothing is recorded until the user clicks "Enable Tracker".

Setup. One row per step with a mark (✓ source `active`, ! `fallback` or `off`, – no health record yet), its title, and a line beginning "On: …" with what the tracker records while ✓, "Off: …" with what it records instead while !. A row that is not ✓ also shows numbered steps and which bundle the grant belongs to and why. Rows name bundles by their file name in System Settings and Finder, `<APP_NAME>` and `TimeTrackingAgent` (in Debug both with " Debug"). Configuration of other programs is offered as snippets, never installed; an info popover says where each goes.

| Step | Source | Actions |
|---|---|---|
| Background tracker (required) | `SMAppService` | Enable Tracker, Open Login Items |
| Open `<APP_NAME>` at login | `SMAppService.mainApp` | "Open at Login", Open Login Items |
| Accessibility (required) | `window` | Open System Settings, "Show TimeTrackingAgent in Finder" |
| Automation | `browser`, `terminal` | "Ask for Access", Open System Settings |
| Full Disk Access (optional) | `history`, `knowledge` | Open System Settings, "Show `<APP_NAME>` in Finder", "Restart Tracker" while the tracker is enabled |
| iCloud Drive | `shared_folder` | "Record on This Mac" while another Mac records, which writes this Mac's UUID to `blocks/owner`; while the app copies the log (4.1) the row is ✓ |
| Neovim title (optional) | `editor` | Copy Snippet (`set title titlestring=nvim\ %F`) |
| tmux hooks (optional) | `tmux_events` | Copy Snippet (`focus-events` and one `set-hook` line per hook of 3.1, through `run-shell -b`) |
| Claude Code hooks (optional) | `agent_events` | Copy Snippet (the hooks JSON, each command ending in `&`) |
| Remote shells (optional) | `remote_shell` | Copy Snippet (an OSC 7 prompt hook for the remote shell, and `set -g set-titles on` with a title format for the remote tmux) |

"Restart Tracker" restarts the agent and re-reads the status; on failure the section reads "The tracker could not be restarted. Disable and enable it to try again." "Ask for Access" asks macOS whether `<APP_NAME>` may control each browser and terminal the tracker reads through Apple Events and that is open, since macOS can ask only for open apps. One line then gives the answers: "Allowed: Safari and iTerm2.", "Declined: Google Chrome; turn it on in System Settings.", "Couldn't ask: `<names>`.", or "None of the browsers and terminals the tracker asks are open." The row's mark still comes from the tracker's health.

Recording. Each source's name on screen and status: "On" in the secondary color, "Limited: `<reason>`" or "Off: `<reason>`" in the warning color; "The tracker hasn't reported yet." before the first `current.json`.

Exclude from Tracking. Shown only when the Activity section opened the pane with a draft: a focused field with the drafted value, "Cancel", and "Add to Settings File" (default). Adding inserts the value into its list in `[privacy]` and confirms: "Added `<value>` to the `<list>`." A list is named on screen with its key, such as "excluded apps (exclude_apps)".

Files. "Settings file": its path, "Open in Editor" (the app chosen for `.toml` files, else TextEdit), and "Show in Finder"; both first create the default file when there is none. "Activity logs": the path of `blocks/`, "Show in Finder", and an info button with the commands `tracker-event forget-day <date>` and `tracker-event reapply-exclusions <from> <to>`, with today's real date in the examples. The footer says the tracker picks up a change within 30 seconds. Without the App Group container both paths read "Not available".

A file that does not decode reads "The settings file has an error on line `<n>`: `<description>`. Fix it in the editor." or "In the settings file, `<table.key>` can't be used: …"; a list that is not an array reads "In the settings file, exclude_apps under [privacy] must be a list, like ["com.example.app"]."; a failed write reads "Couldn't write the settings file: `<reason>`".

## 8. Testable behaviors

- TRK-1. With no events, a 10 minute run under a fake clock inserts exactly 20 live Samples.
- TRK-2. Lock, sleep, wake, a user switch, an app switch, and a `tracker-event` line each take a Sample within 1 second, timed at the event.
- TRK-3. States follow 3.4, including the `passive_limit` cutoff, audio-only apps never being passive, and display-off Samples being `idle`; a Sample that is neither `active` nor `passive` has no foreground Item.
- TRK-4. Without a terminal adapter, the fallback picks the tty with the most recent input and `terminal` reports `fallback`.
- TRK-5. A matching pane title yields a document only while the pane's command is that editor.
- TRK-6. An editor RPC silent for 200 ms falls through to process arguments within 100 ms plus the timeout.
- TRK-7. A Claude Code session inside tmux gives the session title as `session`; a tmux pane without one gives `session:window.pane`.
- TRK-8. The workspace follows 2.3: the nearest folder with a root marker; a worktree resolved to its main repository; never the home folder; a `localhost` URL takes the workspace of the process listening on its port; a URL pattern's capture names the workspace, and a repository whose `origin` matches the capture gives its folder; a host prefixes the location, and without one gives `<host>:`; otherwise the app.
- TRK-9. A Safari URL without a `History.db` visit in the last 24 hours is recorded as a private window with no URL; Chromium incognito is never read.
- TRK-10. A Sample that is `idle`, `locked`, or `otherUser` lists the busy coding agents, tmux sessions with recent input, and running `job_commands` as background Items; an `asleep` one lists none.
- TRK-11. For each setting of 7.2, a matching fixture leaves no excluded path, domain, session, or title in any Sample, date file, or `current.json`, through every entry point listed there.
- TRK-12. For each default redaction filter of 4.3, the Sample keeps the full value, and the block log and `current.json` have only the secret part replaced by `(private)`.
- TRK-13. `insert` drops the Samples inside a deleted range and marks the dates of the others; `replace` with an equal list changes nothing and marks no date.
- TRK-14. A gap longer than `idle_close` without live Samples gets one `appUsage` Sample every 30 seconds through each app interval there; reading the same `knowledgeC.db` again marks no date.
- TRK-15. An unexpected Knowledge schema sets `knowledge` to `off` with a reason and inserts nothing.
- TRK-16. The daily drop deletes the Samples of whole dates older than 90 days and moves the cutoff date; no date is marked, the date files of frozen dates stay as they are, and a late Sample on a frozen date is not stored.
- TRK-17. A new DeviceEvent for a device-date replaces that device's iOS Samples of that date; a fetch without new events marks no date.
- TRK-18. Screen Time thresholds at minutes 1 to 20, a 10 minute gap, and minutes 21 to 30 yield two iPhone blocks split at the gap, with the set's label as app and workspace.
- TRK-19. With `synced_safari_history` off, no `safariHistory` Sample is stored and `CloudTabs.db` is not opened; on, visits last as in 6.1 and runs are attributed to one device or to `remote`; visits arriving after the loop read past their time still form a block.
- TRK-20. The rebuild loop takes the oldest changed date first and today last, and skips a frozen date.
- TRK-21. A block closes after `idle_close` without an attentive Sample, at the end of its credited time, with the reason `idle`; shorter gaps earn nothing.
- TRK-22. A `locked`, `asleep`, `otherUser`, or `paused` Sample with no other device's use following within `idle_close` closes the open block at once, with that state as the reason; when the agent stops after an attentive Mac Sample, the block closes with `stopped`, and when the Mac sleeps after the user moved to the iPhone, with `idle`.
- TRK-23. 15 minutes in one workspace then 15 in another split at the change with the reason `split`; two workspaces alternating every 2 minutes for 40 minutes never split.
- TRK-24. A block reaching `max_block` is cut at the best change point in its last 30 minutes, or there when it has none, with the reason `maxLength`; a mostly passive one runs to `max_passive_block`.
- TRK-25. With `min_block` 10 minutes and `idle_close` 5 minutes: 4 minutes active, 6 idle, then 8 active give one block over all 18 minutes; 20 active, 7 idle, then 4 active and nothing more give one block of 31 minutes in place of the first; 4 minutes active alone gives no block.
- TRK-26. A block from 23:30 to 00:40 is in the file of its start date, whole, and the next date's first block starts after it; while it is open after midnight, every new Sample rebuilds its date, `current.json` holds it, and the next date's file stays as it is; once it closes, the next date is rebuilt.
- TRK-27. 15 minutes of Mac work, 5 minutes on the iPhone while the Mac is locked (its first Screen Time minute ending 70 seconds after the lock), and 15 more minutes of Mac work form one block with 30 minutes on the Mac and 5 on the iPhone, and the locked Mac's background Items still count; iPhone use during the Mac's attention is a background Item that adds no foreground time; overlapping iPhone and iPad use forms one block in which an iPad automation wins its minutes over the iPhone's "Everything"; a named Screen Time set and "Everything" on one iPhone count its minutes once; synced Safari history fills only time no other device claims.
- TRK-28. Twenty minutes of work with a busy coding agent, then forty minutes away while it stays busy, give one foreground block whose background list holds the agent for the block's range and one background block from the block's end for the rest; an item under `min_background_item` is dropped, and a background block without items is not written; a gap of `idle_close` without background Items ends a background block.
- TRK-29. A date file has the header first and one block per line in the order of `s`, omits empty, absent, and 0 values, and reads back as written; a reader skips an unknown line or key.
- TRK-30. A reader polling a date file or `current.json` never sees a partial file; a rebuild that forms the same blocks leaves the date file untouched.
- TRK-31. A date file present only as an iCloud Drive placeholder is not written; once downloaded, the date is written.
- TRK-32. After a lock notification 29 seconds before a tick, `presence.since` equals the notification time within 1 second.
- TRK-33. After the agent is killed, readers report it delayed 90 seconds and not running 2 minutes after its last tick, by the rule of 4.4.
- TRK-34. With container writes denied, the Mac app's container copy matches the local date files within 5 seconds of each write, `settings.toml` edits propagate, and `shared_folder` reports `fallback`.
- TRK-35. An unknown socket command gets `error` and changes nothing.
- TRK-36. `delete-block <s> <e>` over two blocks deletes both and their Samples and adds a deleted range; late DeviceEvents, synced visits, and app usage for that time form no block again; on a frozen date it removes the blocks from the file and leaves the other lines byte-identical.
- TRK-37. After a domain is added to `exclude_domains`, `reapply-exclusions` removes it from the Samples and frozen date files in range, and the rebuilt dates hold no trace of it; `forget-day` deletes the date the same way.
- TRK-38. Changing `idle_after` changes the next Sample's state without a restart.
- TRK-39. Without Accessibility, Samples carry the app and appID only and `window` reports `fallback`.
- TRK-40. The `--replay` flag reproduces the expected date files byte for byte and exits 0; a changed threshold makes it exit non-zero.
- TRK-41. The `--record` output contains no home path, host name, or URL path of the live run.
- TRK-42. Two tick requests arriving while a step waits for `ps` start one tick, after that step; no two steps run at once.
- TRK-43. A copy of another app's database during which its WAL changed is made again and matches the files as they are afterwards.
- TRK-44. A second agent finds `agent.lock` taken and does not start; an agent that can't open `agent.lock` does not start either.
- TRK-45. A command still running at its deadline is stopped and answers nothing; the tick goes on.
- TRK-46. With `settings.toml` replaced by an iCloud Drive placeholder, the agent and the readers keep the exclusions they had.
- TRK-47. A settings file with a key the tracker doesn't know decodes like the same file without it.
- TRK-48. The block summary follows 2.8: workspaces by share, at most `summary_lines` item lines, items that read the same merged into one line, workspaces under `summary_min_share` folded into "+n more", at most three background items, and the footer only with reconstructed time.
- TRK-49. The pane's dot, button, and setup marks follow 7.4 and update within 5 seconds; the agent is not registered until "Enable Tracker".
- TRK-50. The pane writes `settings.toml` only to create the default file when there is none (never over a hand-edited file, and never while an iCloud Drive placeholder stands for it) and to add a drafted exclusion, which changes nothing in the file but the one inserted value.
- TRK-51. The Full Disk Access row names the app by its bundle file name (`<APP_NAME>`, in Debug `<APP_NAME> Debug`) in its steps and its Finder button, which reveals the app bundle; the Accessibility row names and reveals `TimeTrackingAgent` (in Debug `TimeTrackingAgent Debug`).
- TRK-52. While the tracker is enabled and the Full Disk Access row is not ✓, the row offers "Restart Tracker", which restarts the agent once and re-reads the status; it is not offered otherwise.
- TRK-53. The "Open `<APP_NAME>` at login" row is ✓ when the app's login item is enabled; otherwise its action registers it, or opens Login Items when approval is required.
- TRK-54. The tmux snippet sets `focus-events` and has one hook line per hook of 3.1, each calling `tracker-event tmux <hook>` with its own hook name, which the agent accepts; the Claude Code snippet does the same for its three hooks; every call runs in the background and discards its output and exit status.
- TRK-55. "Ask for Access" on the Automation row asks for exactly the browsers and terminals the agent reads through Apple Events, skipping those that are not open, and the row then lists each open app's answer; before the first ask the row shows no such line.
- TRK-56. With the remote shell snippet installed on a host, an ssh session's Samples carry the host, folder, remote tmux session, and command, and `remote_shell` reports `active`.
- TRK-57. After "Disable Tracker", or the login item turned off in System Settings, and a later "Enable Tracker", the gap between them gets no `appUsage` Samples; a gap while the agent was merely not running does.
- TRK-58. An iPhone app automation opened at 23:50 and closed at 00:20 gives Samples on both dates, also when the close arrives in a later fetch, and a pausing Focus on from Friday 18:00 to Monday 08:00 pauses all four dates.
- TRK-59. Renaming an iPhone changes its name in every rebuilt block, also of dates without new events, and a synced Safari visit from it counts as the same device as its own Samples.
- TRK-60. A date skipped because its file was an iCloud Drive placeholder is rebuilt once the download completes.
- TRK-61. While the rebuild loop works through a month of changed dates, ticks keep `health.last_tick` younger than 90 seconds.
- TRK-62. A short block at 00:03 after a block that ended at 23:58 merges into it in the earlier date's file, also when the iPhone's Samples that bridge the gap arrive an hour later; a 15-minute block at 00:03 starts the next date's file.
- TRK-63. A background block ends with `idle` after `idle_close` without background Items, with `split` at the next foreground block, and with `maxLength` at `max_background_block`; a glance that forms no foreground block doesn't end it.
- TRK-64. With `synced_safari_history` off, `synced_safari` is not in `health.sources`, and no reader shows a problem for it.
- TRK-65. On a new Mac whose block log already holds dates, the dates before the agent's first start are frozen: the first fetch of DeviceEvents leaves their files as they are, and `reapply-exclusions` edits them in place.
- TRK-66. Work until 22:00, sleep from 23:00 to 08:00, and work again: the first pass after waking settles the evening's date, and the morning's blocks form in the next date's file; `--replay` of the same Samples writes both files.
- TRK-67. With `blocks/owner` naming another Mac, the agent writes no date file and reports `shared_folder` `off`; "Enable Tracker" or "Record on This Mac" on this Mac writes its UUID there, and from then on the other Mac's agent writes none; on the Mac that doesn't record, `delete-block` and `forget-day` answer `error`.
- TRK-68. After a flight from New York to Berlin, rebuilding a date formed in New York uses its New York midnights, and no block appears in two date files or in none; on the night daylight saving time ends, an iPhone's device-dates meet at one midnight.
- TRK-69. A clock set 200 days ahead moves the cutoff date by one day per daily drop; a deletion pending on the date before the new cutoff, a date file still downloading, and a device-date waiting for a redo each reach their file before the date freezes.
- TRK-70. `forget-day` for today and `delete-block` with an end after now delete up to now, and the next tick's Sample is stored.
- TRK-71. A fetch that skips DeviceEvent records of another app version stores the others, moves the token past all of them, and reports `device_events` `fallback`; the next fetch without such records reports `active`; the daily purge deletes such records before the cutoff date from CloudKit.
- TRK-72. Every tmux command the agent runs passes `-u`, so a terminal tab whose foreground program is a tmux client gives the session's active pane.
