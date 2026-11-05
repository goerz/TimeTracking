# Spec: Activity Tracking Component

## 1. Scope

The tracker records where the user's attention goes, in detail on the Mac and more coarsely on iPhone and iPad, as activity blocks ("blocks"), which the Calendar and the Activity section show. It records raw identifiers (session names, paths, domains, app names), never assigns a project, area, or client (the user does that when making entries from blocks in the Calendar), and never reads or writes time entries. It runs as the tracker agent, a login item (section 5), with no UI of its own beyond the Mac app's settings pane (7.4). The iOS collectors are in `spec_ios.md`, the `DeviceEvent` record in `spec_data_and_sync.md`.

Collection ignores the setting Midnight (`spec_data_and_sync.md` §8): every day, date, "today", and midnight in this spec is the real local one, blocks close at 00:00, and the logs hold real dates. Only readers place blocks on the days they show (`spec_activity.md` §1.1).

## 2. Design

### 2.1 Overview

Every 30 seconds, and at once when the user switches apps or tmux panes or locks the screen, the agent takes a *sample* of the Mac (2.3): a time, a presence state, one *primary item* for what the frontmost window shows while the user is present, and any number of *background items* for work going on without attention, such as a busy coding agent or a running build, which never count as active time. An item is three strings from coarse to fine: *context* (the app or terminal session), *subject* (the piece of work), and *detail* (the thing in hand). Each item also has a *workspace*: the tmux session, project folder, website, or app the work belongs to, whichever app shows it (2.2). The iPhone and iPad allow no such access; the iOS app records coarser events, which the agent turns into items of the same form (6.2).

The samples of all devices for one day form one *timeline* (2.4), cut into *blocks* (2.5), each with a *summary* of its main items (2.6). Work done while the user was away forms *background stretches* between the blocks (2.7). Section 4 lists the records.

Principles:

1. Attention, not activity. Presence comes from input and the display, never from what apps do: tabs reloading after a display wake are not attention.
2. One timeline of the user. Blocks never overlap; the iPhone and iPad fill the time away from the Mac rather than forming a parallel track.
3. Blocks are derived. A late iPhone event changes a day's blocks as if it had arrived on time (2.8).
4. Privacy where data enters. Exclusions (7.2) apply before anything is written, and only the block log and the live activity in `LiveState` (4.4) leave the Mac. Never recorded: keystrokes, clipboard, screenshots, message bodies, terminal command lines (they can carry tokens), password manager contents, and anything of a private browser window beyond the browser name.
5. Degrade instead of failing. Every source that depends on a permission, configuration, or an undocumented format has a fallback and reports its status (3.5).

### 2.2 Items and workspaces

Every item carries the device it was observed on.

| Level | Terminal | Browser | Document | Other app |
|---|---|---|---|---|
| context | `tmux:paper` | `safari` | `skim` | `mail` |
| subject | `draft` (tmux window) or `~/Documents/Papers/2026_Noise` (cwd) | `github.com/owner/repo` | `~/Documents/Papers/2026_Noise` (work folder) | `Inbox` (window title) |
| detail | `nvim notes.tex` | `pull/123` | `notes.pdf` | (none) |

A coding agent session as a background item is `claude` with the session's name as subject, a running build the pane's tmux session and cwd with the program's name.

The context groups time by app in the Activity section. The workspace groups it by work across apps, so a PDF in Skim and Neovim in a plain terminal in the same folder share one, and switching between them never splits a block. It decides where blocks split and names the block. The first rule that applies gives it:

1. A terminal pane in a tmux session: the session (`tmux:paper`), not the folder, because a session often holds panes in several folders of one piece of work. Without tmux: the work folder of the pane's cwd.
2. A notebook tab on `localhost`: the workspace of the pane that owns the port.
3. A file or folder: its work folder.
4. A URL on a code host: domain plus owner (`github.com/owner`). Any other URL: the bare domain.
5. Anything else: the app name.

A work folder is the nearest ancestor containing a `root_markers` entry, otherwise the folder `group_depth` levels below its watched root (`roots`), or the first level below a `deep_folders` entry; outside the roots, the folder itself.

### 2.3 Samples

A tick takes a sample every 30 seconds. Events advance the tick, so that a change is timed when it happens: app activation, the tmux and Claude Code hooks (3.1), and the presence events lock, sleep, display sleep, and user switch (3.4), which are recorded in the sample.

1. Presence (3.4). The sample is not attentive, and has no primary item, when there was no input for `idle_after` and no passive item is frontmost or the display is off (`idle`), the screen is locked (`locked`), the Mac sleeps (`asleep`), or another user owns the console (`other_user`). Otherwise it is `active`, or `passive` by the rule below.
2. The frontmost app and its focused window through Accessibility (no Screen Recording).
3. The primary item. Terminals follow 3.1, browsers 3.3. Finder gives its front window's folder, a window with an `AXDocument` its work folder and file name, chat apps their workspace and channel from the title, and any other app its name and window title.
4. The background items, also while the user is away but not while the Mac sleeps: every busy coding agent session, every tmux client with input in the last 30 seconds in a session other than the primary item's, and `job_commands` in tmux panes other than the primary item's.
5. Exclusions (7.2), then the sample is written.

Apps in `passive_apps`, tabs on `passive_domains`, and meeting and screen-sharing apps count as attention while frontmost with the display on, even without input, up to `passive_limit`; such samples are `passive`. Audio-only apps never count.

### 2.4 The timeline

One timeline per day merges everything recorded for that day:

- The Mac's samples, live or reconstructed from the Knowledge store (3.2), claim the time they cover.
- The stretches of the iPhone and iPad (6.2) and of synced Safari history (6.1) fill the rest, as one sample every 30 seconds. Where they overlap, the most specific wins: the iOS app, then automations, web extension tabs, named ladder sets, "Everything", and synced Safari history last; on a tie the later start.
- Another device's stretch during the Mac's attention becomes a background item of that time (2.7).
- Within another device's stretch, the Mac's samples that are not attentive, and its lock and sleep events, are dropped, so a block runs on from the Mac to the iPhone and back.

### 2.5 Blocks

Each attentive sample credits its primary item with the time up to the next sample, at most 60 seconds, when that sample is attentive or an event that closes the block; otherwise it credits nothing.

An attentive sample opens a block when none is open. The open block takes every following attentive sample until it closes on the first of these:

- After `idle_close` without an attentive sample: it ends at its last attentive sample. Shorter gaps are absorbed: they lie inside the block but add no credited time.
- Lock, sleep, display sleep, or a user switch: it ends at the event's time, unless another device's use covers it (2.4).
- Midnight, when attention continues across it: it ends at 00:00 and the next attentive sample opens a new block, so no block spans two dates, like stored entries.
- A split, by the split test.
- Reaching `max_block` (`max_passive_block` when mostly passive) without a split: it ends at the best change point in its last 30 minutes, or at the current sample when there is none, and the rest stays open as a new block.

The split test runs after every sample once the open block is longer than `split_after`. The candidates are the points where the credited time moves from one workspace to another, with at least `min_half` of credited time on each side. The two sides of a candidate are compared as shares of their credited time per workspace, by weighted Jaccard distance: 1 minus the sum over workspaces of the smaller share divided by the sum of the larger share. The candidate with the largest distance (the earliest on a tie) is the best change point. If it reaches `split_threshold`, the part before it closes as a block. So moving from one workspace to another splits at the move, while alternating between two never does, because both sides hold the same mix.

No block is shorter than `min_block` (from start to end). A block that closes shorter is held back, unwritten, with a merge window of `idle_close` plus its own length:

1. An attentive sample within the window after its end reopens it, and the gap is absorbed (across a lock or sleep too).
2. Otherwise it merges into the previous block when that ended within the window before its start, on the same date, and the two together stay within `max_block` (`max_passive_block` when mostly passive). The merged block keeps the previous block's start.
3. Otherwise it is dropped.

Nothing merges across midnight, a Focus that suspends collection, or agent shutdown.

### 2.6 The block summary

When a block closes:

1. Sum the credited seconds per primary item and device.
2. Merge the items of one device sharing context and subject when they have more than three details (`nvim (5 files)`).
3. Drop items under `summary_min_share` or under 60 seconds, but keep the top item of every workspace present for at least 3 minutes.
4. Order by first appearance, cap at `summary_lines`.
5. Store the dominant workspace and its share.
6. Store the active seconds per device, most first, and the seconds reconstructed from the Knowledge store.
7. Append the background items with at least 5 minutes within the block's range (2.7).

### 2.7 Background work

Every Mac sample, attentive or not, credits each of its background items with the time up to the next Mac sample, at most 60 seconds, and another device's use during the Mac's attention counts for the time it covers. Time within a block's range goes to that block, including its absorbed idle gaps.

The rest forms *background stretches*, beside the blocks rather than as blocks: a block measures attention, and the time between blocks stays away time (`spec_activity.md` §1.8), while a stretch still tells what went on for a project. A gap of `idle_close` or more without background time, a block, or midnight separates two stretches. A stretch lists its background items with at least 5 minutes and spans their time; without such an item it is not recorded. Today's last stretch is recorded once `idle_close` has passed without background work.

### 2.8 Forming a day again

The agent forms today's blocks and stretches again on every tick, and a past day's whenever an input for that day arrives (iPhone events, a Knowledge reconstruction, synced Safari history), and replaces the day's lines in both logs when they changed. A new or changed block's detail keeps the old detail entries within its range.

Today's last block may still be open (4.4). A past day's last block closes at its last attentive sample, or at midnight. The agent remembers the last day it formed, so its first tick on a later day first forms every day since, and a block still open when it stopped closes on its own day. On SIGTERM (logout, shutdown, unregistration) it forms today once more with the open block closed, then exits.

## 3. Sources

### 3.1 Terminal

The focused pane's tty comes from a terminal adapter: WezTerm through `wezterm cli`, iTerm2 and Terminal.app through AppleScript. Without one, it is the tty below the frontmost terminal with the most recent input. A tmux client on that tty gives the session and the active pane's window name, command, cwd, and title; without tmux, the tty's foreground process and its cwd. A tmux window's name is the subject when the user set it; otherwise the cwd is.

The pane's foreground program refines the item:

- Editors give `<program> <file>`. The file comes from the pane title matched against `title_patterns`, trusted only while the pane's command is that editor, then Neovim RPC (200 ms timeout), then process arguments. While the title works, RPC cross-checks it every 10 minutes per pane and reports a mismatch to health.
- Claude Code is recognized by a live session of `~/.claude/sessions/<pid>.json` in the pane's process tree, which gives session name, cwd, tmux target, and busy or idle status; transcripts are never read. Other `agent_processes` give process name plus cwd.
- Interpreters (Julia, Python, R, Node) give the command as detail. A notebook server's listening port is registered, so a browser tab on it inherits the pane's item.
- Shells give the file modified below the cwd in the last 30 seconds, if any, as detail.
- Any other command gives its name as detail.

The tmux hooks `client-session-changed`, `after-select-window`, `after-select-pane`, and `client-focus-in` (which needs `set -g focus-events on`), and the Claude Code hooks `UserPromptSubmit`, `Stop`, and `SessionEnd`, may call `tracker-event tmux <hook>` and `tracker-event agent <hook>`, which write one line to the agent's socket and advance the tick. The hook's name is required. The snippets of 7.4 run the tool in the background and discard its output and exit status, so neither a stopped tracker nor the tick it waits for (over a second) holds up tmux or Claude Code, which cancels `SessionEnd` hooks after 1.5 seconds. The sources `tmux_events` and `agent_events` are `active` when such an event arrived in the last 7 days.

### 3.2 Knowledge store

The macOS Knowledge store (`knowledgeC.db`, Full Disk Access) records app intervals, Safari dwell time, and display state. The agent reads a copy and sets the source `off` when the schema is not the expected one. At agent start and every 15 minutes it reconstructs samples for periods it was down (one per 30 seconds of each app interval, counted in `rec`, 4.2), reading the last 24 hours again because usage can be written late. Safari dwell times go to the detail log.

### 3.3 Browsers

The active tab of a frontmost browser is read through Apple Events: Safari's current tab, and for Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi) the active tab, skipping incognito windows. Browsers without a scripting dictionary, or with Automation denied, give `AXURL` plus title, and "Private Browsing" in the title marks a private window.

Safari private windows write no history, so a sampled Safari URL with no visit in the last 24 hours in `History.db` is recorded as `safari (private)` without the URL, until its visit shows up. Without Full Disk Access, Safari URLs are reduced to the domain.

At block close, the detail log gets every visit in the block's range from Safari's `History.db` (`origin = 0`) and each Chromium profile's `History`. Histories are read from copies, never the live files; a copy during which the database or its WAL changed is made again, up to three times.

Items drop a URL's query and fragment, except forum topic ids (`t`, `topic`, `tid`). Code host pull request and issue paths reduce to their number, `localhost:<port>` maps to the owning pane's item, and domains in the `summary_domain_only` categories reduce to the domain. The detail log keeps full URLs, apart from private domains.

### 3.4 Presence and files

Idle seconds, lock, display sleep, system sleep, and user switches come from system events that need no permission; console ownership is checked each tick.

An FSEvents stream on `roots`, skipping `prune_names`, records modified files into the detail log of the block. FSEvents delivers late and without a time, so a change counts at the file's modification time when that lies within the last minute, else at its delivery.

### 3.5 Health and fallbacks

Each source reports `active`, `fallback`, or `off` (cannot run) in the health record (4.4), with a reason when not `active`. Screens show the status as "On", "Limited", or "Off", the source by its name on screen, and the reason as written: a consequence for the user, never a mechanism. Mechanisms go to the log.

| Id | Name on screen | Fallback, with its reason |
|---|---|---|
| `window` | Window titles | App name only ("Accessibility is off; only app names are recorded") |
| `terminal` | Terminal tab | Process tree plus last input ("`<App>` can't report its front tab; the tab is guessed from recent activity") |
| `tmux` | tmux sessions | The tty's foreground process and cwd ("tmux is not running") |
| `editor` | File open in Neovim | Editor RPC, then process arguments, then cwd |
| `agents` | Coding agents | Process plus cwd, busy state unknown ("Claude Code not found; when it is working can't be told") |
| `tmux_events` | tmux hooks | The tick alone ("No tmux hook event in the last 7 days; switches are noticed up to 30 seconds late") |
| `agent_events` | Claude Code hooks | The tick alone ("No Claude Code hook event in the last 7 days; changes are noticed up to 30 seconds late") |
| `browser` | Browser tab | `AXURL` plus title ("`<App>` can't report its tab; the address is read from the window", "Automation is off for `<App>`; the address is read from the window") |
| `history` | Browser history | Sampled tabs only ("Full Disk Access is off; Safari pages are recorded by site only") |
| `knowledge` | App usage history | Off ("macOS app usage history was not found", "Full Disk Access is off; macOS app usage history can't be read", "macOS changed how it stores app usage; this version can't read it") |
| `files` | Modified files | Off ("None of the watched folders in the settings file exist") |
| `shared_folder` | iCloud Drive | `fallback` "Copied to iCloud Drive while the app is open"; `off` "iCloud Drive is off; activity stays on this Mac" (4.1) |
| `device_events` | iPhone and iPad | `fallback` "Checking…" until the first 5-minute fetch, "Couldn't reach iCloud; trying again in 5 minutes" after a failed one; `off` "iCloud is not available; iPhone and iPad activity doesn't reach this Mac" |
| `synced_safari` | Safari on other devices | Off ("Turned off in the settings file", "Full Disk Access is off") |

## 4. Storage

### 4.1 Tiers and folders

| Tier | Where | Content | Retention |
|---|---|---|---|
| Samples | Agent folder, `samples.sqlite` | Samples, reconstructed samples, synced Safari visits, iPhone and iPad events, and deleted time | 90 days |
| Block log | Shared folder, `blocks/<mac>/YYYY-MM.jsonl` | One line per closed block and per background stretch | Permanent |
| Detail log | Agent folder, `Activity/detail/YYYY-MM-DD.jsonl` | Per block: all items, URLs, modified files, presence transitions, dwell times | Permanent |
| Current state | Agent folder, `Activity/current.json` | Open block, primary item, presence, health | Each tick |
| Settings | Shared folder, `settings.toml` | Section 7 | Permanent |

The agent folder is `<App Group container>/Library/Application Support/TimeTracking/`. It also holds the socket `tracker.sock` and `agent.lock`, which the running agent holds, so a second agent exits. Nothing in it leaves the Mac. The shared folder is `Activity/` in the product's iCloud Drive container, outside `Documents/`, and holds only `blocks/` and `settings.toml`.

Each Mac's agent writes only its own subfolder of `blocks/`, named by the Mac's hardware UUID, so iCloud Drive never has to choose between two versions; readers read every subfolder. Month files directly in `blocks/` come from before the subfolders: readers still read them, and on start each agent moves the lines under a header with its own `dev` into its subfolder and leaves another Mac's.

Every write of a log or `current.json` replaces the whole file, so a reader sees a day as it was before or after a rewrite, never in between; when a day changes, its detail file is replaced before its month file. A month file that iCloud Drive holds only as a placeholder is never written: the agent asks for its download and writes the day once it is here.

Without iCloud Drive, the agent folder's `Activity/` takes the shared folder's place (`shared_folder` reports `off`). When the container exists but cannot be written, the agent uses that folder too and `shared_folder` reports `fallback`, which alone tells the Mac app to copy each changed month file into the container and keep the two `settings.toml` identical (newer modification time wins).

### 4.2 Block log format

```json
{"type":"header","format":1,"tz":"-04:00","dev":"macbook","contexts":{"tmux:paper":"com.github.wez.wezterm","safari":"com.apple.Safari","Mail":"ladder","claude":"claude"},"keys":{"s":"start (local time)","e":"end (local time)","a":"active seconds","dev":"devices [device, active seconds]","rec":"seconds reconstructed from the Mac's app usage history","g":"dominant group","gs":"share of the dominant group","items":"items [context, subject, detail, seconds, device]","bg":"background items [context, subject, detail, seconds, device]"}}
{"s":"2026-10-28T09:10:00","e":"2026-10-28T09:44:30","a":1860,"dev":[["macbook",1620],["iPhone",240]],"rec":0,"g":"tmux:paper","gs":0.71,"items":[["tmux:paper","draft","nvim (5 files)",1080,"macbook"],["safari","github.com/owner/repo","pull/123",540,"macbook"],["Mail","Mail","",240,"iPhone"]],"bg":[["claude","refactor-parser","",720,"macbook"]]}
{"type":"background","s":"2026-10-28T12:10:00","e":"2026-10-28T12:48:30","bg":[["claude","refactor-parser","",2280,"macbook"]]}
```

Each month file starts with a header. Another follows a time zone change and precedes the first line using a context not yet in `contexts`, which maps context keys to bundle identifiers (or process names). The header's `dev` names the Mac that wrote the file. The first header also carries `keys`, a legend readers ignore. Readers skip objects with another `type` than `header` and `background`, and ignore unknown keys.

The times `s` and `e` are local, on one date, and `s` identifies the block. The key `a` is the sum of credited item seconds before the summary cut (less than `e` minus `s` when idle gaps were absorbed). Each entry of `dev` is the Mac's name, an iPhone's or iPad's, or `remote` for unattributed synced Safari history (6.1). The key `rec` is the part of `a` reconstructed from the Knowledge store, and `g` and `gs` are the dominant workspace and its share of `a`. Idle time is the absence of a block. Lines are in time order.

### 4.3 Detail log format

One file per local date, headers as in 4.2. A block line has `items` uncut, so it holds totals per item but not their order, plus `urls`, `files`, `presence` (the transitions in and around the block, so every gap between blocks is covered), and `dwell`. The legend of the first header labels them too: `urls` "URL visits [time, browser, URL, title]", `files` "modified files [time, path]", `presence` "presence transitions [time, state]", `dwell` "Safari dwell times [time, URL, seconds]". Only the recording Mac reads this log.

### 4.4 Current state

Rewritten on every tick and presence event; never copied to the shared folder.

```json
{"format":1,"dev":"macbook","block":{"s":"2026-10-28T09:10:00","a":1080,"dev":[["macbook",1080]],"rec":0,"g":"tmux:paper","gs":0.71,"items":[["tmux:paper","draft","nvim (5 files)",1080,"macbook"]],"bg":[]},"primary":["tmux:paper","draft","nvim notes.tex"],"presence":{"state":"active","since":"2026-10-28T09:10:00","last_input":"2026-10-28T09:44:27"},"health":{"last_tick":"2026-10-28T09:44:30","version":"1.0 (42)","sources":[{"id":"terminal","name":"Terminal tab","status":"active","reason":""}]}}
```

The `block` is today's open block as of now, with the keys of 4.2 but without `e` (or `null`). The value of `primary` is `null` while the user is not attentive. In `presence`, `since` is the time of the event or input that set the state, not of the tick that noticed it. The list `health.sources` holds every source of 3.5.

Every reader derives the tracker's liveness from `health.last_tick` by one rule: the tracker is running while the last tick is younger than 2 minutes, and not running when it is 2 minutes old or older or `current.json` is missing. While running, a last tick of 90 seconds or older counts as delayed. The Tracker pane, the Activity footer, the menu bar warning, the Timer's idle detection, and `agentRunning` in `LiveState` all use this rule.

The Timer reads `presence` for its own idle detection (`spec_timer.md`). The Mac app copies the tracker fields into `LiveState` (`spec_data_and_sync.md` §4.1); they are already filtered by the exclusions.

## 5. Agent

The agent, `TimeTrackingAgent.app`, is a headless login item with `KeepAlive` (`spec_architecture.md`), always team-signed because TCC keys grants to signing identities. Ticks run one at a time, and the requests arriving during a tick share one follow-up tick. A command the agent runs (`ps`, `tmux`, `lsof`) that is still running after 5 seconds is stopped and counts as unreadable, so a hung one cannot stall the ticks.

The flag `--record <folder>` writes adapter outputs and samples as fixtures, with home-directory paths, host names, and URL paths replaced by placeholders. The flag `--replay <fixture>` runs block forming over a recorded sample stream, compares with `<fixture>.expected.jsonl`, and exits non-zero on a difference. The flag `--unregister` removes the login item registration and exits.

| Permission | Granted to | Gives |
|---|---|---|
| Accessibility (required) | `TimeTrackingAgent.app` | Window titles, documents, browser addresses |
| Automation, per browser and scriptable terminal | The app | The browser's tab and the terminal's front tab; macOS asks at first use, or on "Ask for Access" (7.4) |
| Full Disk Access (optional) | The app | The Knowledge store, Safari's history and synced tabs |

macOS checks Accessibility for the agent itself, but attributes the agent's file access and Apple Events to its responsible app (`AssociatedBundleIdentifiers`, `spec_architecture.md` §1.4). The app therefore carries the Apple Events entitlement and `NSAppleEventsUsageDescription` as well as the agent; without them macOS refuses the Apple Events with `-1743` and never asks. A new Full Disk Access grant reaches the running agent only after a restart.

## 6. Other Apple devices

### 6.1 Synced Safari history

With `synced_safari_history` on, the agent stores Safari's `History.db` visits with `origin = 1` for the timeline. It is off by default: attribution is weak, and it duplicates the iOS web extension, which outranks it. Such visits can arrive hours late, so each read covers the last 24 hours again. A visit lasts until the next one when that follows within 5 minutes. A run of visits without a longer gap belongs to `remote`, unless `CloudTabs.db` (polled every 5 minutes) shows that within it, or within 5 minutes of it, exactly one device's tab set gained a visited URL; then to that device's name.

### 6.2 Collected by the iOS app

The iOS app writes raw, labeled `DeviceEvent` records per device, exclusions applied (`spec_ios.md` §9). The agent turns each device-day's events into stretches of the timeline on the device's name:

| Source | Mechanism | Stretch |
|---|---|---|
| `ladder` | DeviceActivity thresholds at rising minutes of daily use of each user-labeled set of apps, categories, or domains, on a schedule from midnight to midnight | The minutes since the set's previous counted step, with the set's label as context, subject, and workspace; "Everything" (any app) has the device's name as context and workspace and no subject |
| `webext` | Safari Web Extension, tab activations and URL changes | Up to a minute, until the next tab, as a browser item under the rules of 3.3 |
| `intent` | App Intent "Log activity event" for Shortcuts automations | A minute, or from `appOpened` to `appClosed` within `max_block`, with its label |
| `app` | The iOS app's foreground transitions | From foreground to background within `max_block`, else a minute |
| `focus` | Focus filter | None; a Focus that suspends collection closes the open block, unless the Mac's attention covers that moment |

## 7. Settings and exclusions

All settings live in `settings.toml` in the shared folder, read by the agent and the iOS collection. A file that cannot be read (a parse error, or an iCloud Drive placeholder) leaves the settings in force, exclusions included, until it can. The file is the user's to edit. The app writes it only to create the default file when there is none, and to add an exclusion drafted in the Activity section, which inserts one value and keeps every other byte. The agent applies a change from the next tick.

### 7.1 Defaults

The default file holds these values, with a comment on every setting. A missing key takes its default. Durations read `"30s"`, `"5m"`, `"3h"`; `~` in a path is the home folder; domains match themselves and their subdomains; apps are named by bundle identifier. The setting `idle_after` governs blocks only; the Timer's idle prompt has its own threshold. The switch `record_commands` has no effect.

```toml
[presence]
idle_after = "2m"
passive_apps = [
    "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
    "com.apple.ScreenSharing", "com.apple.QuickTimePlayerX",
]
passive_domains = ["youtube.com", "netflix.com", "meet.google.com"]
passive_limit = "3h"

[blocks]
split_after = "20m"
min_half = "10m"
min_block = "10m"
split_threshold = 0.7
idle_close = "5m"
max_block = "90m"
max_passive_block = "3h"
summary_lines = 6
summary_min_share = 0.05

[files]
roots = ["~/Documents", "~/Desktop"]
prune_names = [
    ".git", "node_modules", "__pycache__", ".ipynb_checkpoints", ".venv",
    "venv", "build", "_build", ".build", ".cache", ".Trash", "target",
    "DerivedData", "dist", "Pods", ".swiftpm", ".pytest_cache",
]
root_markers = [".git"]
group_depth = 1
deep_folders = []

[terminal]
title_patterns = { nvim = '^nvim (/.+)$' }
agent_processes = ["claude", "codex", "aider"]
job_commands = ["make", "gmake", "latexmk", "pytest", "cargo", "swift", "npm"]

[devices]
synced_safari_history = false

[privacy]
record_commands = false
private_agent_paths = ["~"]
name_only_apps = ["com.1password.1password"]
# The other lists of 7.2 are empty.

[browser]
summary_domain_only = ["search", "news", "shopping", "entertainment"]

[browser.categories]
research = ["arxiv.org", "doi.org", "scholar.google.com", "semanticscholar.org"]
code = ["github.com", "gitlab.com", "stackoverflow.com", "readthedocs.io"]
ai = ["claude.ai", "chatgpt.com"]
search = ["google.com", "duckduckgo.com", "kagi.com", "bing.com"]
news = ["nytimes.com", "theguardian.com", "news.ycombinator.com"]
shopping = ["amazon.com", "ebay.com"]
entertainment = ["youtube.com", "netflix.com", "reddit.com"]
```

### 7.2 Exclusions

Exclusions apply wherever data enters (sampler, histories, file stream, Knowledge backfill, device merge, iOS web extension), case-insensitively, to what is recorded from then on. Calendar and Activity also apply them to past activity when they show it (`spec_activity.md` §4); the log files keep what they hold until `reapply-exclusions` rewrites them (7.3). A path is checked wherever it appears (editor file, cwd, `AXDocument`, Finder folder, modified file, `file://` URL); an excluded file in an ordinary session hides the file and keeps the session.

| Setting | Matches | Effect |
|---|---|---|
| `exclude_paths` | A path at or below an entry | Subject and detail `(private)`, workspace `private`; time kept |
| `exclude_keywords` | A path component starting with an entry | As `exclude_paths` |
| `exclude_tmux_sessions` | A session name | Context `tmux:(private)`; window, cwd, file dropped |
| `private_agent_paths` | An agent session's cwd, exactly | Session name and status only |
| `name_only_apps` | A bundle identifier | App name only |
| `exclude_apps` | A bundle identifier | Nothing recorded; the time is a gap |
| `private_domains` | A domain | Domain only, everywhere |
| `exclude_domains` | A domain | `<browser> (private)`; no detail-log visits |
| `exclude_title_keywords` | A title substring | Title dropped |

### 7.3 Rewrite commands

Settings changes never touch past logs. The agent is the only writer of the logs, so rewrites go through its socket: one line of words (double quotes around a word with spaces), answered by `ok` or `error <reason>`. Each command replaces the files it touches atomically and keeps unaffected lines byte-identical. Their dates and times are real local ones, whatever Midnight says.

- The command `delete-block <s> [<e>]` deletes the block starting at `<s>`, or with `<e>` everything from `<s>` to `<e>`, so a block the Calendar showed goes whole even when a tick has cut it since. "Delete This Activity…" in the Calendar always sends both.
- The command `forget-day <date>` deletes the date.
- The command `reapply-exclusions <from> <to>` applies the current exclusions to those dates' blocks, stretches, and samples, and drops a stretch left without items.

Deleting removes what the block or day was formed from and records the time as deleted, so late events never form a block there again; then the day is formed again (2.8). The last two are run with `tracker-event`.

The reasons are protocol text; the Mac app logs them and shows its own sentence: "The tracker could not be reached.", "The tracker is not running." (nothing listens), "This activity is no longer in the logs." (`no block at …`), "The tracker is restarting. Try again in a moment." (`the tracker is stopping`), and "The tracker could not change the logs." for any other.

### 7.4 The Tracker settings pane

The last pane of the Mac app's settings window (`spec_timer.md` §8). While visible it re-reads the status every 5 seconds. It has no editors for exclusions or options and no maintenance controls: the file is where settings are changed, and rewriting logs is a command-line task. From top to bottom:

Status. A dot and one line by the liveness rule of 4.4: green "Tracker running · checked 12 s ago", yellow "Tracker delayed · last checked 1 min ago", red "Tracker not running", gray "Tracker off" when the agent is not registered; then "Tracker version". One button by `SMAppService` status: "Enable Tracker" (`notRegistered`), "Open Login Items" (`requiresApproval`), "Disable Tracker" (`enabled`, after confirmation). Nothing is recorded until the user clicks "Enable Tracker".

Setup. One row per step with a mark (✓ source `active`, ! `fallback` or `off`, – no health record yet), its title, and a line beginning "On: …" with what the tracker records while ✓, "Off: …" with what it records instead while !. A row that is not ✓ also shows numbered steps and which bundle the grant belongs to and why. Rows name bundles by their file name in System Settings and Finder, `<APP_NAME>` and `TimeTrackingAgent` (in Debug both with " Debug"). Configuration of other programs is offered as snippets, never installed; an info popover says where each goes.

| Step | Source | Actions |
|---|---|---|
| Background tracker (required) | `SMAppService` | Enable Tracker, Open Login Items |
| Open `<APP_NAME>` at login | `SMAppService.mainApp` | "Open at Login", Open Login Items |
| Accessibility (required) | `window` | Open System Settings, "Show TimeTrackingAgent in Finder" |
| Automation | `browser`, `terminal` | "Ask for Access", Open System Settings |
| Full Disk Access (optional) | `history`, `knowledge` | Open System Settings, "Show `<APP_NAME>` in Finder", "Restart Tracker" while the tracker is enabled |
| iCloud Drive | `shared_folder` | None; while the app copies the log (4.1) the row is ✓ |
| Neovim title (optional) | `editor` | Copy Snippet (`set title titlestring=nvim\ %F`) |
| tmux hooks (optional) | `tmux_events` | Copy Snippet (`focus-events` and one `set-hook` line per hook of 3.1, through `run-shell -b`) |
| Claude Code hooks (optional) | `agent_events` | Copy Snippet (the hooks JSON, each command ending in `&`) |

"Restart Tracker" restarts the agent and re-reads the status; on failure the section reads "The tracker could not be restarted. Disable and enable it to try again." "Ask for Access" asks macOS whether `<APP_NAME>` may control each browser and terminal the tracker reads through Apple Events and that is open, since macOS can ask only for open apps. One line then gives the answers: "Allowed: Safari and iTerm2.", "Declined: Google Chrome; turn it on in System Settings.", "Couldn't ask: `<names>`.", or "None of the browsers and terminals the tracker asks are open." The row's mark still comes from the tracker's health.

Recording. Each source's name on screen and status: "On" in the secondary color, "Limited: `<reason>`" or "Off: `<reason>`" in the warning color; "The tracker hasn't reported yet." before the first `current.json`.

Exclude from Tracking. Shown only when the Activity section opened the pane with a draft: a focused field with the drafted value, "Cancel", and "Add to Settings File" (default). Adding inserts the value into its list in `[privacy]` and confirms: "Added `<value>` to the `<list>`." A list is named on screen with its key, such as "excluded apps (exclude_apps)".

Files. "Settings file": its path, "Open in Editor" (the app chosen for `.toml` files, else TextEdit), and "Show in Finder"; both first create the default file when there is none. "Activity logs": the path of `blocks/`, "Show in Finder", and an info button with the commands `tracker-event forget-day <date>` and `tracker-event reapply-exclusions <from> <to>`, with today's real date in the examples. The footer says the tracker picks up a change within 30 seconds. Without the App Group container both paths read "Not available".

A file that does not decode reads "The settings file has an error on line `<n>`: `<description>`. Fix it in the editor." or "In the settings file, `<table.key>` can't be used: …"; a list that is not an array reads "In the settings file, exclude_apps under [privacy] must be a list, like ["com.example.app"]."; a failed write reads "Couldn't write the settings file: `<reason>`".

## 8. Testable behaviors

- TRK-1. With no events, a 10 minute run under a fake clock writes exactly 20 samples.
- TRK-2. Presence verdicts follow 2.3, including the `passive_limit` cutoff and audio-only apps never being passive.
- TRK-3. Without a terminal adapter, the fallback picks the tty with the most recent input and `terminal` reports `fallback`.
- TRK-4. A matching pane title yields a file only while the pane's command is that editor.
- TRK-5. An editor RPC silent for 200 ms falls through to arguments, then cwd, within 100 ms plus the timeout.
- TRK-6. A `localhost:<port>` tab gets the item and workspace of the pane that registered the port.
- TRK-7. A Safari URL without a `History.db` visit in the last 24 hours becomes `safari (private)` and leaves the samples; Chromium incognito yields `<browser> (private)` with no URL.
- TRK-8. For each setting of 7.2, a matching fixture leaves no excluded path, domain, session, or title in any sample, log line, or `current.json`, through every entry point listed there.
- TRK-9. A block closes at its last attentive sample after `idle_close`; shorter idle gaps are not counted in `a`.
- TRK-10. Lock, sleep, display sleep, and a user switch close the block at the event time.
- TRK-11. No block has `s` and `e` on different dates; a block open at midnight ends at 00:00:00.
- TRK-12. 15 minutes in one workspace then 15 in another splits within one tick of the change; two workspaces alternating every 2 minutes for 40 minutes never split.
- TRK-13. A block reaching `max_block` closes at the best change point in its last 30 minutes, or the current tick when there is none; a mostly passive one runs to `max_passive_block`.
- TRK-14. Summaries follow 2.6, and `a` never exceeds `e` minus `s`.
- TRK-15. Header lines appear per 4.2 (month start, time zone change, new context); every other line has every block key.
- TRK-16. The shared folder holds only `blocks/` and `settings.toml`, with no `urls`, `files`, or `presence` keys.
- TRK-17. A reader polling `current.json` never sees a partial file.
- TRK-18. After a lock notification 29 seconds before a tick, `presence.since` equals the notification time within 1 second.
- TRK-19. After the agent is killed, readers report it delayed 90 seconds and not running 2 minutes after its last tick, by the rule of 4.4.
- TRK-20. With container writes denied, the Mac app's container copy matches the local block log within 5 seconds of each append, `settings.toml` edits propagate, and `shared_folder` reports `fallback`.
- TRK-21. A `tracker-event` line advances the tick within 1 second; an unknown socket command gets `error` and changes nothing.
- TRK-22. The `reapply-exclusions` command, after a domain is added to `exclude_domains`, removes its items and visits from both logs and the samples in range, leaving other lines byte-identical; `delete-block` and `forget-day` do the same for their block or day.
- TRK-23. Changing `idle_after` changes the next sample's verdict without a restart.
- TRK-24. An unexpected Knowledge schema sets `knowledge` to `off` with a reason and reconstructs nothing; with the expected schema the time the agent was down forms blocks whose `rec` equals `a`.
- TRK-25. Without Accessibility, samples carry the app name only and `window` reports `fallback`.
- TRK-26. Samples and merged `DeviceEvent` records older than 90 days are deleted.
- TRK-27. With `synced_safari_history` off, no `remote` time is recorded and `CloudTabs.db` is not opened; on, synced visits form blocks and runs are attributed as in 6.1.
- TRK-28. Ladder minutes 1 to 20, a 10 minute gap, and minutes 21 to 30 yield two blocks of the iPhone split at the gap, with the set's label as context and workspace.
- TRK-29. The `--replay` flag reproduces the expected file byte for byte and exits 0; a changed threshold makes it exit non-zero.
- TRK-30. The `--record` output contains no home path, host name, or URL path of the live run.
- TRK-31. The pane's dot, button, and setup marks follow 7.4 and update within 5 seconds; the agent is not registered until "Enable Tracker".
- TRK-32. The pane writes `settings.toml` only to create the default file when there is none (never over a hand-edited file, and never while an iCloud Drive placeholder stands for it) and to add a drafted exclusion, which changes nothing in the file but the one inserted value.
- TRK-33. The Full Disk Access row names the app by its bundle file name (`<APP_NAME>`, in Debug `<APP_NAME> Debug`) in its steps and its Finder button, which reveals the app bundle; the Accessibility row names and reveals `TimeTrackingAgent` (in Debug `TimeTrackingAgent Debug`).
- TRK-34. While the tracker is enabled and the Full Disk Access row is not ✓, the row offers "Restart Tracker", which restarts the agent once and re-reads the status; it is not offered otherwise.
- TRK-35. The "Open `<APP_NAME>` at login" row is ✓ when the app's login item is enabled; otherwise its action registers it, or opens Login Items when approval is required.
- TRK-36. The tmux snippet sets `focus-events` and has one hook line per hook of 3.1, each calling `tracker-event tmux <hook>` with its own hook name, which the agent accepts; the Claude Code snippet does the same for its three hooks; every call runs in the background and discards its output and exit status.
- TRK-37. "Ask for Access" on the Automation row asks for exactly the browsers and terminals the agent reads through Apple Events, skipping those that are not open, and the row then lists each open app's answer; before the first ask the row shows no such line.
- TRK-38. The first header of each block-log month file and detail-log day file carries `keys`, naming exactly the keys of that log's block lines with the labels of 4.2 and 4.3; later headers carry none.
- TRK-39. With `min_block` 10 minutes and `idle_close` 5 minutes: 4 minutes active, 6 idle, then 8 active give one block over all 18 minutes; 20 active, 7 idle, then 4 active and nothing more give one block of 31 minutes in place of the first; 4 minutes active alone gives no block; a short block is never merged across midnight; and in the logs the merged block's line replaces the previous one.
- TRK-40. With `min_block` 10 minutes: 15 minutes of Mac work, 5 minutes on the iPhone while the Mac is locked, and 15 more minutes of Mac work form one block with 30 minutes on the Mac and 5 on the iPhone; iPhone use during the Mac's attention is a background item that adds nothing to `a`; overlapping iPhone and iPad use forms one block in which an iPad app wins its minutes over the iPhone's "Everything"; synced Safari history fills only time no iPhone stretch claims; a deleted block stays deleted when late iPhone events for its time arrive.
- TRK-41. A sample that is idle, locked, or taken while another user owns the console lists the busy coding agents and running jobs as background items; an asleep one lists none.
- TRK-42. Twenty minutes of work with a busy coding agent, then forty minutes away while it stays busy, give one block whose `bg` lists the agent for the block's range and one background stretch from the block's end for the rest; background time in an absorbed idle gap counts for the block; an item under 5 minutes forms no stretch; a gap of `idle_close` separates two stretches; today's last stretch is recorded only after `idle_close` without background work; no stretch spans midnight or a block.
- TRK-43. A background stretch line carries `type` `background`, `s`, `e`, and `bg`, and reads back as written; reapplied exclusions remove its excluded items and drop it when none is left.
- TRK-44. Each Mac writes only `blocks/<mac>/`: forming a day again leaves another Mac's blocks of that day, and readers show both; on start the agent moves its own lines out of a month file directly in `blocks/` and leaves another Mac's.
- TRK-45. Replacing a day writes its detail file and then its month file, each in one rename; when the detail file cannot be written, the month file is unchanged.
- TRK-46. A block still open when the agent stopped without a SIGTERM is closed on its own day by the agent's first tick days later.
- TRK-47. Two tick requests arriving while a tick waits for `ps` start one follow-up tick, after the first; no two ticks run at once.
- TRK-48. A copy of another app's database during which its WAL changed is made again and matches the files as they are afterwards.
- TRK-49. A second agent finds `agent.lock` taken and does not start.
- TRK-50. A file event delivered 20 seconds after the save is recorded at the save; one whose file was last modified an hour ago, at its delivery.
- TRK-51. A month file present only as an iCloud Drive placeholder is not written; once it is downloaded, the day joins the month's other days.
- TRK-52. A command still running at its deadline is stopped and answers nothing; the tick goes on.
- TRK-53. With `settings.toml` replaced by an iCloud Drive placeholder, the agent and the readers keep the exclusions they had.
- TRK-54. `delete-block <s> <e>` over two blocks deletes both and their samples.
- TRK-55. Synced Safari visits arriving after the agent read past their time still form a remote block; the Knowledge backfill likewise reads the last 24 hours again.
