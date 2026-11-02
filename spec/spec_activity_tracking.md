# Spec: Activity Tracking Component

## 1. Scope

The tracker agent (see `components.md`) records where the user's attention goes on the Mac, and with less detail on iPhone and iPad, as a permanent log of activity blocks ("blocks"). It never assigns a project, area, or client to a block (the user does, making entries in the Calendar of `spec_calendar.md`), never reads the time store, and never shows UI; its settings pane belongs to the Mac app (7.4). The iOS collectors are implemented in `spec_ios.md`; the `DeviceEvent` record is defined in `spec_data_and_sync.md`.

## 2. Design

### 2.1 Principles

1. A 30 second tick takes a sample. Events (app activation, pane change, agent hooks, lock, sleep, user switch) refine the timing between ticks.
2. Presence is decided by input and display state, never by app activity (tabs reloading after a display wake are not attention).
3. Every sample has one primary item (where attention is) and zero or more secondary items (a busy coding agent, a running build). Blocks are formed from primary items.
4. The tracker records raw identifiers (session names, paths, domains, app names) and never maps them to projects.
5. Exclusions (7.2) apply before anything is written. Raw samples stay local; only closed blocks reach the permanent logs.

### 2.2 The item

An item has three recorded levels and one derived key, all strings.

| Level | Meaning | Terminal | Browser | Document |
|---|---|---|---|---|
| context | Kind of place | `tmux:paper` | `safari` | `skim` |
| subject | The piece of work | `draft` (window) or `~/Documents/Papers/2026_Noise` (cwd) | `github.com/owner/repo` | `~/Documents/Papers/2026_Noise` |
| detail | The thing in hand | `nvim notes.tex` | `pull/123` | `notes.pdf` |
| group key | Derived; decides where blocks split | `tmux:paper` | `github.com/owner` | `~/Documents/Papers/2026_Noise` |

The group key comes from the first rule that applies:

1. A terminal item in a multiplexer: the session name. Without a multiplexer: the work folder of the pane's cwd (rule 3).
2. A notebook tab on `localhost`: the group key of the pane that owns the port.
3. A file or folder: the nearest ancestor containing a `root_markers` entry, otherwise the folder `group_depth` levels below its watched root, one level deeper below `deep_folders`.
4. A URL on a code host: domain plus owner. Any other URL: the bare domain.
5. Anything else: the app name.

### 2.3 Sources and fallbacks

Each source is detected at runtime and reports `active`, `fallback`, or `off` (cannot run) in the health record (4.4), with a reason when not `active`. Screens show the status as "On", "Limited", or "Off", the source by its name on screen (the library's table `TrackerSourceHealth.names`, so a reader shows the name for an id), and the reason as written: a consequence for the user, never a mechanism ("Full Disk Access is off; Safari pages are recorded by site only"). Details such as a schema mismatch or CloudKit's error go to the log.

| Id | Name on screen | Source | Depends on | Fallback |
|---|---|---|---|---|
| `window` | Window titles | Window title, `AXDocument` | Accessibility | App name only ("Accessibility is off; only app names are recorded") |
| `terminal` | Terminal tab | Focused terminal pane | A terminal adapter (3.1) | Process tree of the frontmost terminal plus last input time ("`<App>` can't report its front tab; the tab is guessed from recent activity") |
| `tmux` | tmux sessions | Session, window, pane | tmux running | Foreground process and cwd of the pane's tty |
| `editor` | File open in Neovim | Editor file | Editor sets its terminal title | Editor RPC, then process arguments, then cwd |
| `agents` | Coding agents | Coding agent sessions | Claude Code's `~/.claude/sessions/*.json` (undocumented) | Process plus cwd, busy state unknown ("Claude Code not found; when it is working can't be told") |
| `tmux_events` | tmux hooks | tmux push events | User-installed tmux hooks | The tick alone ("No tmux hook event in the last 7 days; switches are noticed up to 30 seconds late") |
| `agent_events` | Claude Code hooks | Coding agent push events | User-installed agent hooks | The tick alone ("No Claude Code hook event in the last 7 days; changes are noticed up to 30 seconds late") |
| `browser` | Browser tab | Active tab | Automation per browser | `AXURL` plus title ("`<App>` can't report its tab; the address is read from the window", "Automation is off for `<App>`; the address is read from the window") |
| `history` | Browser history | Full browser history | Full Disk Access (Safari), profile discovery (Chromium) | Sampled tabs only; Safari URLs reduced to the domain ("Full Disk Access is off; Safari pages are recorded by site only") |
| `knowledge` | App usage history | Backfill, Safari dwell times | Full Disk Access, expected Knowledge store schema | Off ("macOS app usage history was not found", "… can't be read", "macOS changed how it stores app usage; this version can't read it") |
| `files` | Modified files | Modified files | An existing folder in `roots` | Off ("None of the watched folders in the settings file exist") |
| `shared_folder` | iCloud Drive | Block log in iCloud Drive | iCloud Drive, container write access | `fallback` "Copied to iCloud Drive while the app is open" (4.1); without iCloud Drive `off` "iCloud Drive is off; activity stays on this Mac" |
| `device_events` | iPhone and iPad | iPhone and iPad collection | iCloud; a fetch every 5 minutes | `fallback` "Checking…" until the first fetch and "Couldn't reach iCloud; trying again in 5 minutes" after a failed one; without iCloud `off` "iCloud is not available; iPhone and iPad activity doesn't reach this Mac" |
| `synced_safari` | Safari on other devices | Safari history from other devices | `synced_safari_history` and Full Disk Access | Off ("Turned off in the settings file", "Full Disk Access is off") |

### 2.4 Resolver chain per tick

1. Presence (3.4). The sample is `idle`, and nothing else runs, if idle time exceeds `idle_after` and no passive item is frontmost (2.5), or if the display is off, the screen is locked, or another user owns the console.
2. The frontmost app and its focused window through Accessibility (`AXTitle`, `AXDocument`, `AXURL` for browsers; no Screen Recording).
3. Dispatch by bundle identifier: terminals to 3.1, browsers to 3.3. Chat apps give workspace and channel from the title. Meeting and screen-sharing apps give the meeting or host name. Document apps give `AXDocument`, else the title; Finder gives the front window's folder. Any other app gives its name plus the window title.
4. Secondary items: every busy coding agent session; every tmux client with input in the last 30 s in a session other than the primary's; `job_commands` running in non-active panes.
5. Apply the exclusions and write the sample: time, state, primary, secondaries, and debug fields (bundle id, filtered title, tmux target).

### 2.5 Passive attention

Apps in `passive_apps`, tabs on `passive_domains`, and meeting and screen-sharing apps count as attention while frontmost with the display on, even without input, up to `passive_limit`. Audio-only apps never count.

### 2.6 From samples to blocks

Blocks are formed from one stream of samples per local day, the user's timeline of 2.8. Each active sample appends to the open block, opening one if none is open; idle samples do not extend it. The block closes on any of:

- Idle for `idle_close`; the end is the last active sample, and shorter gaps are absorbed.
- Screen lock, sleep, display sleep, or a user switch, at the event time, unless another device's use covers it (2.8).
- Local midnight: the block closes at 00:00 and the next active sample opens a new one, so no block spans two dates.
- The split test.
- Reaching `max_block` without a split: the block closes at the best change point in the last 30 minutes, or at the current tick. A mostly passive block may run to `max_passive_block`.

The split test runs on every tick once the open block exceeds `split_after`. For each candidate split point with at least `min_half` on each side, it compares the two sides as time-weighted distributions over group keys by weighted Jaccard distance: 1 minus the sum over keys of the smaller share divided by the sum of the larger share. If the best candidate reaches `split_threshold`, the first part closes as a block.

No block is shorter than `min_block` (from `s` to `e`). A block that closes shorter is held back, unwritten, and merged or dropped. Its merge window is `idle_close` plus its own length:

1. An active sample within the window after its end reopens it: it continues as the open block, and the gap is absorbed like a short idle gap (across a lock or sleep too).
2. Otherwise, when the window has passed: if the previous block ended within the window before its start, on the same date, and the two together stay within `max_block` (`max_passive_block` when mostly passive), the two merge into one block with the previous block's start, which replaces the previous block in both logs.
3. Otherwise it is dropped.

Nothing merges across midnight, a Focus that suspends collection, or agent shutdown.

### 2.7 The block summary

When a block closes:

1. Sum the seconds per primary item and device.
2. Merge items of one device sharing context and subject when their details would take more than three lines (`nvim draft (5 files)`).
3. Drop items under `summary_min_share` and under 60 s, but keep the top item of every group key present for at least 3 minutes.
4. Order by time, cap at `summary_lines`.
5. Append secondaries that ran at least 5 minutes, among them another device's use during the Mac's attention (2.8).
6. Store the dominant group key and its share.
7. Store the active seconds per device, most first, and the seconds reconstructed from the Knowledge store.

```
09:10-09:44  tmux:paper (71%)  tmux:paper nvim draft (3 files) 18m · safari github.com/owner/repo pull/123 9m · mail Inbox 4m  + claude refactor-parser (busy 12m)
```

### 2.8 One timeline

The block log describes the user, not each device. Blocks are formed from one stream of samples per local day that merges everything recorded for that day, so no two blocks share time and one block may span several devices:

- The Mac's samples, live (2.4) or reconstructed from the Knowledge store (3.2), claim the time they are credited with.
- The stretches of the iPhone and iPad (6.2) and of synced Safari history (6.1) cover the rest. Where they overlap, the most specific wins: the iOS app, then automations, web extension tabs, named ladder sets, "Everything", and synced Safari history last; on a tie the later start. Their time becomes samples every 30 seconds.
- Another device's stretch during the Mac's attention becomes a secondary of the Mac's sample: it appears in `bg` and adds nothing to `a`.
- Within another device's stretch, the Mac's samples without attention (idle, locked, asleep) and its lock and sleep events are dropped, so a block runs on from the Mac to the iPhone and back; the split test still separates them where the activity differs.

Every item carries its device, and every block its time per device (`dev`) and its reconstructed time (`rec`).

The agent stores what the stream is made of for 90 days: the samples, the samples reconstructed from the Knowledge store, the synced Safari visits with their attributed device, and the iPhone and iPad events (4.1). It forms today's blocks again on every tick, and a past day's whenever an input of that day arrives (iPhone events through iCloud, a Knowledge reconstruction, synced Safari history), and replaces the day's lines in the block log and its detail file when they changed. A past day's last block closes at its last active sample, or at midnight. A new or changed block's detail keeps the URLs, files, presence transitions, and dwell times of the day's old detail lines within its range.

## 3. Sources

### 3.1 Terminal

The focused pane's tty comes from a terminal adapter (WezTerm through `wezterm cli`, iTerm2 and Terminal.app through AppleScript; kitty optional). Without one, it is the tty of the frontmost terminal's descendant processes with the most recent input (tmux `client_activity`, else the tty's access time). A tmux client on that tty (on every server socket under `$TMUX_TMPDIR` or `/tmp/tmux-<uid>/`) gives the session and the active pane's window name, command, cwd, title, and pid; without tmux, the tty's foreground process and its cwd.

The pane's foreground program refines the item:

- Editors: the pane title matched against `title_patterns`, trusted only while the pane's command is that editor; then editor RPC (Neovim: the socket of the `nvim --embed` descendant, `expand("%:p")`, 200 ms timeout, cached per pane); then process arguments; then cwd. While the title works, RPC cross-checks it every 10 minutes per pane and reports a mismatch to health.
- Coding agents, recognized by executable path or title: for Claude Code, `~/.claude/sessions/<pid>.json` gives session name, cwd, tmux target, and busy or idle status; transcripts are never read live, and never under `private_agent_paths`. Other `agent_processes` give process name plus cwd.
- Interpreters (Julia, Python, R, Node): cwd as subject, command as detail. A notebook server's listening port is registered so a browser tab on it inherits the pane's item.
- Shells: the cwd only.
- Commands in `job_commands`: cwd plus program name.

The tmux hooks `client-session-changed`, `after-select-window`, `after-select-pane`, and `client-focus-in` (the terminal window gains focus; it needs `set -g focus-events on`), and the Claude Code hooks `UserPromptSubmit`, `Stop`, and `SessionEnd`, may call `tracker-event tmux <hook>` and `tracker-event agent <hook>`, which write one line to the agent's socket and advance the tick. The event needs the hook's name; `tracker-event tmux` alone is rejected. The snippets of 7.4 discard the tool's output and exit status, so a stopped tracker never interrupts tmux or Claude Code; the sources `tmux_events` and `agent_events` are `active` when such an event arrived in the last 7 days, which the Setup rows show.

### 3.2 Knowledge store

The macOS Knowledge store (`~/Library/Application Support/Knowledge/knowledgeC.db`, Full Disk Access) records app intervals (`/app/usage`), Safari dwell time (`/app/webUsage`), and display state (`/display/isBacklit`). The agent reads a copy of the database and its WAL, and sets the source `off` when the schema is not the expected one. At agent start and every 15 minutes it reconstructs samples for periods the agent was down (one per 30 seconds of each app interval, counted in `rec`, 2.8) and adds Safari dwell times to the detail log; once a day it cross-checks the agent's app timeline.

### 3.3 Browsers

The active tab of a frontmost browser is read through Apple Events: Safari's current tab `URL` and `name`; for Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi) `URL`, `title`, and the incognito flag, skipping private tabs. Browsers without a scripting dictionary, or with Automation denied, give `AXURL` plus title, and "Private Browsing" in the title marks a private window.

Safari private windows write no history: a sampled Safari URL with no visit in a copy of `History.db` within 3 minutes is recorded as `safari (private)` and the sampled URL is dropped. Without Full Disk Access, Safari URLs are reduced to the domain.

At block close, the detail log gets every visit in the block's range from Safari's `History.db` (`origin = 0`) and each Chromium profile's `History` (copies, never the live files).

Block summaries strip query and fragment except on a short allowlist (code host pull request and issue paths, forum topic ids, arXiv ids), map `localhost:<port>` to the owning pane's item, and reduce domains in the `summary_domain_only` categories to the domain. The detail log keeps full URLs, apart from private domains.

### 3.4 Presence and files

Idle seconds come from `CGEventSource` (no permission); lock from `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`; display sleep, system sleep, and user switches from `NSWorkspace` notifications; console ownership is checked each tick. On wake, the block closes at the sleep time. Time while another user owns the console is idle.

An FSEvents stream on `roots`, skipping `prune_names`, records modified files into the detail log of the block. When a block's terminal items have no resolved file, files modified in the pane's cwd fill the detail.

Never recorded: keystrokes, clipboard, screenshots, message bodies, terminal command lines, password manager contents, and anything of a private browser window beyond the browser name.

## 4. Storage

### 4.1 Tiers and folders

| Tier | Where | Content | Retention |
|---|---|---|---|
| Samples | Agent folder, `samples.sqlite` (GRDB) | One row per tick; reconstructed samples, synced Safari visits, iPhone and iPad events, and deleted time (2.8, 7.3) | 90 days |
| Block log | Shared folder, `blocks/YYYY-MM.jsonl` | One line per closed block | Permanent |
| Detail log | Agent folder, `Activity/detail/YYYY-MM-DD.jsonl` | Per block: all items, URLs, modified files, presence transitions | Permanent |
| Current state | Agent folder, `Activity/current.json` | Open block, primary item, presence, health | Each tick |
| Settings | Shared folder, `settings.toml` | Section 7 | Permanent |

The agent folder is `<App Group container>/Library/Application Support/TimeTracking/` (`spec_architecture.md`); it also holds the socket `tracker.sock` and the health watchdog file, and nothing in it leaves the Mac. The shared folder is `Activity/` in the product's iCloud Drive container, outside `Documents/`, and holds only `blocks/` and `settings.toml`. Without iCloud Drive, the agent folder's `Activity/` takes its place and `shared_folder` reports `off` with "iCloud Drive is off; activity stays on this Mac".

Phase 1 verifies that the agent can write the container. If it cannot, the agent writes `blocks/` and reads `settings.toml` in the agent folder's `Activity/`, and the Mac app copies each changed month file into the container (whole-file replace, `NSFileCoordinator`) and keeps the two `settings.toml` identical (newer modification time wins); `shared_folder` reports `fallback` with "Copied to iCloud Drive while the app is open". The status alone tells the Mac app to copy: `shared_folder` reports `fallback` only in this case, and the reason is display text that nothing compares.

### 4.2 Block log format

```json
{"type":"header","format":1,"tz":"-04:00","dev":"macbook","contexts":{"tmux:paper":"com.github.wez.wezterm","safari":"com.apple.Safari","Mail":"ladder","claude":"claude"},"keys":{"s":"start (local time)","e":"end (local time)","a":"active seconds","dev":"devices [device, active seconds]","rec":"seconds reconstructed from the Mac's app usage history","g":"dominant group","gs":"share of the dominant group","items":"items [context, subject, detail, seconds, device]","bg":"background items [context, subject, detail, seconds, device]"}}
{"s":"2026-10-28T09:10:00","e":"2026-10-28T09:44:30","a":1860,"dev":[["macbook",1620],["iPhone",240]],"rec":0,"g":"tmux:paper","gs":0.71,"items":[["tmux:paper","draft","nvim (3 files)",1080,"macbook"],["safari","github.com/owner/repo","pull/123",540,"macbook"],["Mail","Mail","",240,"iPhone"]],"bg":[["claude","refactor-parser","",720,"macbook"]]}
```

Each month file starts with a header object; another header follows a time zone change and precedes the first block using a context not yet in `contexts`, which maps context keys to bundle identifiers (or process names). The block keys are short to keep lines short, so the first header of each month file also carries `keys`, a legend mapping each block key to a human-readable label (the labels of the example); later headers leave it out, and readers ignore it. Readers skip objects with a `type` and ignore unknown keys. The header's `dev` names the Mac that wrote the file. In a block, `s` and `e` are local times on one date, and `s` identifies the block (no two blocks share time); `a` is the active seconds, the sum of item seconds before the summary cut (less than `e` minus `s` when idle gaps were absorbed); `dev` lists `[device, active seconds]` for each device the block spent time on, most first, where a device is the Mac's name, an iPhone's or iPad's, or `remote` for unattributed synced Safari history (6.1); `rec` is the part of `a` reconstructed from the Knowledge store (3.2); `g` and `gs` are the dominant group key and its share; `items` and `bg` (secondaries) hold `[context, subject, detail, seconds, device]` with `""` for no detail. Idle is the absence of a block.

### 4.3 Detail log format

One file per local date, headers as in 4.2. A block line with `items` uncut, plus `urls` as `[time, browser, url, title]`, `files` as `[time, path]`, and `presence` as the state transitions in and around the block, so every gap between blocks is covered, and `dwell` as Safari dwell times `[time, url, seconds]` from the Knowledge store (3.2) when there are any. The legend `keys` of the first header also labels these: `urls` "URL visits [time, browser, URL, title]", `files` "modified files [time, path]", `presence` "presence transitions [time, state]", `dwell` "Safari dwell times [time, URL, seconds]". The library reads it on the recording Mac only (`detail(for:)`, `spec_data_and_sync.md`).

### 4.4 Current state

Rewritten atomically (temporary file, then rename) on every tick and presence event; never copied to the shared folder.

```json
{"format":1,"dev":"macbook","block":{"s":"2026-10-28T09:10:00","a":1080,"dev":[["macbook",1080]],"rec":0,"g":"tmux:paper","gs":0.71,"items":[["tmux:paper","draft","nvim (3 files)",1080,"macbook"]],"bg":[]},"primary":["tmux:paper","draft","nvim notes.tex"],"presence":{"state":"active","since":"2026-10-28T09:10:00","last_input":"2026-10-28T09:44:27"},"health":{"last_tick":"2026-10-28T09:44:30","version":"1.0 (42)","sources":[{"id":"terminal","name":"Terminal tab","status":"active","reason":""},{"id":"browser","name":"Browser tab","status":"active","reason":""},{"id":"knowledge","name":"App usage history","status":"off","reason":"Full Disk Access is off; macOS app usage history can't be read"}]}}
```

The `block` is today's open block of the timeline (2.8) summarized as of now, with the keys of 4.2 but without `e` (or `null`); `primary` is `null` while idle; `presence.state` is `active`, `passive`, `idle`, `locked`, `asleep`, or `other_user`, and `since` is the time of the event or input that set it, not of the tick that noticed it; `health.sources` lists every source of 2.3.

Every reader derives the tracker's liveness from `health.last_tick` by one rule: the tracker is running while the last tick is younger than 2 minutes, and not running when it is 2 minutes old or older or `current.json` is missing. While running, a last tick of 90 seconds or older counts as delayed. The Tracker pane (7.4), the Activity footer, the menu bar warning, the Timer's idle detection, and `agentRunning` in `LiveState` all use this rule.

The agent pushes nothing. The Timer reads `presence` for its own idle detection (`spec_timer.md`). The Mac app's `LiveStatePublisher` copies the tracker fields of this Mac into `LiveState` (fields and rules in `spec_data_and_sync.md`); they are already filtered by the exclusions.

## 5. Agent

The agent, `TimeTrackingAgent.app`, is a headless login item with `KeepAlive` (bundle, registration, entitlements in `spec_architecture.md`), always team-signed because TCC keys grants to signing identities. macOS attributes the agent's file access to its responsible app, the one `AssociatedBundleIdentifiers` names (`spec_architecture.md` §1.4), so Full Disk Access belongs to the app (`<APP_NAME>.app`, in Debug `<APP_NAME> Debug.app`), not to the agent; Accessibility is checked for the agent itself. Its modules: Presence, Focus, Resolvers (adapters per app), Settings (loads and reloads `settings.toml`), Sampler, Blocker (split, summary, logs, `current.json`), Knowledge, History, Devices (6.2), Events (the socket), and Health. A tick takes under 100 ms.

| Flag | Effect |
|---|---|
| `--record <folder>` | Writes adapter outputs and the run's samples as fixtures, with home-directory paths, host names, and URL paths replaced by placeholders |
| `--replay <fixture>` | Runs the Blocker over a recorded sample stream, compares with `<fixture>.expected.jsonl`, exits non-zero on a difference |
| `--unregister` | Removes the login item registration and exits |

Permissions: Accessibility (required), granted to `TimeTrackingAgent.app`; Automation per browser and scriptable terminal, prompted at first use or by "Ask for Access" (7.4) and, like Full Disk Access, checked for the app because the agent runs on its behalf (so the app carries the Apple Events entitlement and `NSAppleEventsUsageDescription` as well as the agent; without them macOS refuses the agent's Apple Events with `-1743` and never asks); Full Disk Access (optional) for the Knowledge store and Safari's history and synced tabs, granted to the app because the agent runs on its behalf. A new Full Disk Access grant reached the running agent only after a restart, so the Tracker pane offers "Restart Tracker" (7.4).

## 6. Other Apple devices

### 6.1 Synced Safari history

With `synced_safari_history` on, the History module stores Safari's `History.db` visits with `origin = 1` (synced from other devices) for the timeline (2.8): a visit lasts until the next one when that follows within 5 minutes. A run of visits without a longer gap belongs to `remote`, unless `CloudTabs.db` (polled every 5 minutes) shows that within it exactly one device's tab set changed to include a visited URL; then to that device's name. Synced Safari history ranks below every iPhone and iPad stretch.

### 6.2 Collected by the iOS app

The iOS app writes raw, labeled `DeviceEvent` records per device, exclusions applied, with these `source` values:

| Source | Mechanism | Gives |
|---|---|---|
| `ladder` | DeviceActivity: a monitor extension receives `eventDidReachThreshold` at 1, 2, 3, … minutes of daily use of each user-labeled set of apps, categories, or domains ("Everything", "Mail"), schedule midnight to midnight | Minutes of use per set |
| `focus` | Focus filter | Focus on and off |
| `intent` | App Intent "Log activity event" for Shortcuts automations | Exact times with a label |
| `webext` | Safari Web Extension, tab activations and URL changes | Browser items |
| `app` | The iOS app's foreground transitions | App use |

The cap on monitored events is undocumented; phase 7 measures it and sets the ladder steps.

The Devices module turns each device-day's events into stretches of the timeline (2.8) on the device's name: a counted ladder minute covers the minutes since the set's previous counted step, with the set's label as context, subject, and group key, except that "Everything" (any app) is recorded as the device's name as context and group key, without a subject; a web extension tab covers up to a minute, until the next tab, as a browser item under the rules of 3.3; an automation covers a minute, or from `appOpened` to `appClosed`, with its label; the app covers the time from its foreground to its background. Gaps over `idle_close` separate blocks, and a Focus that suspends collection closes the open block. The agent deletes stored events older than 90 days.

## 7. Settings and exclusions

All settings live in `settings.toml` in the shared folder, read by the agent and the iOS collection. The file is the user's to edit in a text editor: the default file comments every setting, and the Tracker pane (7.4) shows the file and opens it. The app writes it only to create the default file when there is none, and to add an exclusion drafted in the Activity section, which inserts one value and keeps every other byte (comments, order, formatting). The agent reloads the file on change and applies it from the next tick.

### 7.1 Defaults

```toml
# Settings of the TimeTracking activity tracker. The tracker reads this file
# whenever it changes and applies it within 30 seconds,
# on this Mac and, for the exclusions, on iPhone and iPad.
#
# Durations: "30s", "5m", "3h". Paths: "~" is the home folder, matched
# case-insensitively. Domains match themselves and their subdomains. Apps
# are named by bundle identifier, such as "com.apple.Safari"; the command
# `osascript -e 'id of app "Safari"'` prints one.

[presence]
# Time without input after which you count as away. Governs activity blocks
# only; the Timer's idle prompt has its own threshold.
idle_after = "2m"
# Apps and sites you watch or listen to without typing count as attention
# while they are in front, for up to passive_limit.
passive_apps = [
    "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
    "com.apple.ScreenSharing", "com.apple.QuickTimePlayerX",
]
passive_domains = ["youtube.com", "netflix.com", "meet.google.com"]
passive_limit = "3h"

[blocks]
# How the timeline is cut into blocks: a block closes after idle_close away,
# is split in two once it is longer than split_after and its two halves (each
# at least min_half) differ by split_threshold (0 to 1), and lasts at most
# max_block (max_passive_block when mostly passive). A block shorter than
# min_block continues when you come back within idle_close plus its length,
# else joins the block before it when that ended within the same time, else
# is not recorded. Its summary lists up to summary_lines items with at least
# summary_min_share of its time.
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
# Watched folders: files you change below these folders are listed with the
# block in which you changed them.
roots = ["~/Documents", "~/Desktop"]
# Folders with these names are not watched.
prune_names = [
    ".git", "node_modules", "__pycache__", ".ipynb_checkpoints", ".venv",
    "venv", "build", "_build", ".build", ".cache", ".Trash", "target",
    "DerivedData", "dist", "Pods", ".swiftpm", ".pytest_cache",
]
# A folder containing one of these is a work folder: its files count as one
# piece of work.
root_markers = [".git"]
# Otherwise, files group under the folder this many levels below their root...
group_depth = 1
# ...or one level deeper below these folders, e.g. "~/Documents/Papers".
deep_folders = []

[terminal]
# Pane title patterns that name the open file; the capture group is the path.
title_patterns = { nvim = '^nvim (/.+)$' }
# Processes recorded as coding agents (process name plus cwd).
agent_processes = ["claude", "codex", "aider"]
# Long-running commands recorded as secondary items.
job_commands = ["make", "gmake", "latexmk", "pytest", "cargo", "swift", "npm"]

[devices]
# Blocks from the Safari history of your other devices, synced through iCloud.
synced_safari_history = false

[privacy]
# Exclusions apply to what is recorded from now on, and Calendar and
# Activity apply them to past activity when they show it. The log files keep what they hold
# until `tracker-event reapply-exclusions <from> <to>` rewrites them.
# Terminal command lines are never recorded; this switch has no effect.
record_commands = false
# Files and folders at or below these paths are recorded as "(private)";
# the time is kept.
exclude_paths = []           # e.g. "~/Documents/Medical"
# Paths with a folder or file name starting with one of these, likewise.
exclude_keywords = []        # e.g. "sparsebundle"
# tmux sessions recorded as "tmux:(private)", without window, folder, or file.
exclude_tmux_sessions = []
# Coding-agent sessions started in exactly these folders keep only their
# name and busy or idle status.
private_agent_paths = ["~"]
# Apps recorded by name only, without window titles or documents.
name_only_apps = ["com.1password.1password"]
# Apps not recorded at all; their time is a gap.
exclude_apps = []
# Sites recorded by domain only, without page addresses or titles.
private_domains = []         # e.g. banks, health portals, tax services
# Sites not recorded; the browser shows as "(private)" while one is open.
exclude_domains = []
# Window and tab titles containing one of these are dropped.
exclude_title_keywords = []

[browser]
# Pages in these categories are summarized by domain only.
summary_domain_only = ["search", "news", "shopping", "entertainment"]

# Categories of sites, named after the key.
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

Exclusions apply wherever data enters (sampler, histories, file stream, Knowledge backfill, device merge, iOS web extension), case-insensitively. A path is checked wherever it appears (editor file, cwd, `AXDocument`, Finder folder, modified file, `file://` URL); an excluded file in an ordinary session hides the file and keeps the session.

| Setting | Matches | Effect |
|---|---|---|
| `exclude_paths` | A path at or below an entry | Subject and detail `(private)`, group key `private`; time kept |
| `exclude_keywords` | A path component starting with an entry | As `exclude_paths` |
| `exclude_tmux_sessions` | A session name | Context `tmux:(private)`; window, cwd, file dropped |
| `private_agent_paths` | An agent session's cwd, exactly | Session name and status only |
| `name_only_apps` | A bundle identifier | App name only |
| `exclude_apps` | A bundle identifier | Nothing recorded; the time is a gap |
| `private_domains` | A domain | Domain only, everywhere |
| `exclude_domains` | A domain | `<browser> (private)`; no detail-log visits |
| `exclude_title_keywords` | A title substring | Title dropped |

### 7.3 Rewrite commands

Settings changes never touch past logs. Three socket commands rewrite the log files and samples they touch: `delete-block <s>`, `forget-day <date>`, and `reapply-exclusions <from> <to>`. `delete-block` and `forget-day` delete what the block or day was formed from (samples, reconstructed samples, synced Safari visits, iPhone and iPad events) and record the time as deleted, so late events never form a block there again; then the day is formed again (2.8). The agent rewrites, replacing each file atomically and keeping unaffected lines byte-identical; the answer is `ok` or `error <reason>`. The UI for `delete-block` is "Delete Block from Log…" in the Calendar's activity column (`spec_calendar.md`); the other two are run with `tracker-event`, which the Tracker pane's "Activity logs" info shows. The reasons are protocol text; the Mac app logs them and shows its own sentence: "The tracker could not be reached." (no socket, or the link to it fails), "The tracker is not running." (nothing listens), "This activity is no longer in the logs." (a reason starting with `no block at`), "The tracker is restarting. Try again in a moment." (`the tracker is stopping`), and "The tracker could not change the logs." for any other.

### 7.4 The Tracker settings pane

The last pane of the Mac app's settings window (`spec_timer.md` §8, which also owns the first-launch alert that opens it, §8.2). While visible it re-reads `current.json` on every change and the login item status every 5 seconds. From top to bottom:

Status. A dot and one line by the liveness rule of 4.4: green "Tracker running · checked 12 s ago", yellow "Tracker delayed · last checked 1 min ago" while delayed, red "Tracker not running", gray "Tracker off" when the agent is not registered; then "Tracker version". One button by `SMAppService` status: "Enable Tracker" (`notRegistered`; registers the agent), "Open Login Items" (`requiresApproval`), "Disable Tracker" (`enabled`; unregisters after confirmation). Nothing is recorded until the user clicks "Enable Tracker".

Setup. One row per step with a mark (✓ source `active`, ! `fallback` or `off`, – no health record yet), its title, one line on what the step does, and an action. The line depends on the mark: "On: …" with what the tracker records while ✓, "Off: …" with what it records instead while !, and the plain sentence while –. The background tracker and the login item rows have no line. The mark shows as a symbol (✓ `checkmark.circle.fill` in green, ! `exclamationmark.triangle.fill` in orange, – `circle.dashed` in `.tertiary`) whose accessibility label is "Done", "Needs attention", or "Not checked yet"; the row's buttons sit in one line below its text, in the small control size. A row that is not ✓ also shows numbered steps and one line on which bundle the grant belongs to and why. Rows name bundles by their file name in System Settings and Finder, `<APP_NAME>` and `TimeTrackingAgent` (in Debug both with " Debug", `spec_architecture.md` §2.2), and each "Show … in Finder" names the bundle it reveals. Rows that need more explanation have an info button at their trailing edge (`info.circle`, borderless), which opens a popover with the explanation and, for the snippet rows, the snippet in a monospaced box with a Copy button.

| Step | Source | On / Off | Action |
|---|---|---|---|
| Background tracker (required) | `SMAppService` | (none) | Enable Tracker / Open Login Items |
| Open `<APP_NAME>` at login | `SMAppService.mainApp` (✓ enabled, ! otherwise) | (none) | "Open at Login" (registers the app) / Open Login Items (`requiresApproval`) |
| Accessibility (required) | `window` | Window titles, open documents, and browser addresses are recorded / only app names | Open System Settings (`Privacy_Accessibility`), "Show TimeTrackingAgent in Finder"; steps: open the pane, drag `TimeTrackingAgent` from the Finder window into the list, turn it on |
| Automation | `browser`, `terminal` | The tracker asks the browser for its current tab and the terminal for its front tab / the tab is read from the browser window, and the terminal tab is guessed | "Ask for Access", Open System Settings (`Privacy_Automation`); steps: open the browsers and terminals you use, click Ask for Access, and click Allow for each; if declined, turn each one on under `<APP_NAME>` in the Automation pane. Why: the tracker runs on behalf of the app; macOS can ask only for open apps, and asks for the others the first time the tracker reads them. Info: which tabs and panes (3.1, 3.3), and how the fallback picks them |
| Full Disk Access (optional) | `history`, `knowledge` | Every Safari page, and times the tracker was not running filled in / Safari pages by site only, those times empty | Open System Settings (`Privacy_AllFiles`), "Show `<APP_NAME>` in Finder" (reveals the app bundle), "Restart Tracker" while the tracker is enabled; steps: open the pane, drag `<APP_NAME>` into the list or click + and choose it, turn it on, and while the tracker is enabled click Restart Tracker. Why: the tracker runs on behalf of the app, so macOS checks the app's access, not the agent's. Info: Safari history and the Knowledge store (3.2, 3.3) |
| iCloud Drive | `shared_folder` | This Mac's activity shows on iPhone and iPad, and theirs here / activity stays on this Mac; while the app copies the log (`fallback`, 4.1) the row is ✓ with "On: this Mac's activity is copied to iCloud Drive while the app is open, and shows on iPhone and iPad." | none |
| Neovim title (optional) | `editor` | The open file is read from the terminal title / the tracker asks Neovim, else knows only the folder | Copy Snippet (`set title titlestring=nvim\ %F`). Info: where it goes (init.vim; the init.lua form) |
| tmux hooks (optional) | `tmux_events` | Switches are recorded the moment they happen / noticed within 30 seconds | Copy Snippet (`set -g focus-events on` and one `set-hook -g <hook> 'run-shell -b "tracker-event tmux <hook> >/dev/null 2>&1 \|\| true"'` line per hook of 3.1). Info: add to `~/.tmux.conf`, reload with `tmux source-file`, `tracker-event` on the PATH |
| Claude Code hooks (optional) | `agent_events` | Start and stop of work are recorded the moment they happen / noticed within 30 seconds | Copy Snippet (the hooks JSON, each command `tracker-event agent <hook> >/dev/null 2>&1 \|\| true`). Info: add to `~/.claude/settings.json`, merging into an existing `hooks` key |

"Restart Tracker" restarts the agent (`launchctl kickstart -k` of its label, run by the app), then re-reads the status; when it fails, the status section reads "The tracker could not be restarted. Disable and enable it to try again." and the exit status goes to the log. "Ask for Access" asks macOS, one app after another, whether `<APP_NAME>` may control each browser of 3.3 and terminal of 3.1 that the tracker reads through Apple Events and that is open (`AEDeterminePermissionToAutomateTarget`, which shows the prompt where there is no answer yet). One line under the buttons then gives the answers by the names the apps show: "Allowed: Safari and iTerm2.", "Declined: Google Chrome; turn it on in System Settings.", "Couldn't ask: `<names>`.", or "None of the browsers and terminals the tracker asks are open." The library holds the list of apps (`AutomationTargets`), which equals the scriptable entries of the agent's browser and terminal tables. The row's mark still comes from the tracker's health. Under `-UITesting` nothing real is asked.

"Copy Snippet" and the popover's "Copy" put the snippet on the pasteboard and read "Copied" with a checkmark for 2 seconds, at the width of the longer title.

Recording. Each source's name on screen (2.3) and its status: "On" in the secondary color, "Limited: `<reason>`" or "Off: `<reason>`" in the warning color; "The tracker hasn't reported yet." before the first `current.json`.

Exclude from Tracking. Shown only when the Activity section opened the pane with a draft (`showTrackerSettings(exclusion:)`): the list's entry name ("App (bundle identifier)", "tmux session", "Site (domain)") with a focused field holding the drafted value, and "Cancel" and "Add to Settings File" (default); the footer reads "Adds the entry to the `<list>` in the settings file, which keeps everything else as it is." Adding inserts the value into its list in `[privacy]` (7 above) and confirms under the settings file: "Added `<value>` to the `<list>`." A list is named on screen with its key in parentheses, for finding it in the file: "excluded apps (exclude_apps)", "apps recorded by name only (name_only_apps)", "excluded sites (exclude_domains)", "private sites (private_domains)", "excluded folders (exclude_paths)", "private coding agent folders (private_agent_paths)", "excluded tmux sessions (exclude_tmux_sessions)", "excluded keywords (exclude_keywords)", "excluded title keywords (exclude_title_keywords)".

Under the settings file, a file that does not decode reads "The settings file has an error on line `<n>`: `<description>`. Fix it in the editor." (TOML syntax) or "In the settings file, `<table.key>` can't be used: …" (a wrong value); a list that is not an array reads "In the settings file, exclude_apps under [privacy] must be a list, like ["com.example.app"]."; a failed write reads "Couldn't write the settings file: `<reason>`". Without the App Group container both paths read "Not available".

Files. "Settings file": the path of `settings.toml` (`~` for the home folder, selectable, truncated in the middle), "Open in Editor" (the app the user chose for `.toml` files, else TextEdit) and "Show in Finder", which opens the folder holding the file; both first create the default file when there is none. "Activity logs": the path of `blocks/`, "Show in Finder" (opens `blocks/`; disabled until the folder exists), and an info button with the maintenance commands: `tracker-event forget-day <date>` and `tracker-event reapply-exclusions <from> <to>` (7.3), with today's date in the examples. The section footer says that exclusions, watched folders, the idle threshold, and site categories are set in the file, each with a comment, and that the tracker picks up a change within 30 seconds.

The pane has no editors for exclusions or options and no maintenance controls: the file is where settings are changed, and rewriting logs is a command-line task.

## 8. Implementation phases

1. Presence, Focus, Settings, generic resolver, samples, `current.json`, health; the container write check (4.1); the pane's status, setup, and sources. Two days of samples calibrate `idle_after`.
2. Terminal adapters and fallback, tmux, the editor chain, agent sessions, push events.
3. Blocker and block log, tuned by replaying phase 1 samples; `LiveState` publication. Block-log readers can start here.
4. Browsers with the private-window test, the detail log, the rewrite commands, the pane's exclusions and maintenance.
5. Knowledge store. The formats of section 4 freeze.
6. Synced Safari history.
7. On iOS: `DeviceEvent` records, the Mac merge, the "Everything" ladder, the event-cap experiment.
8. On iOS: labeled sets, Focus filters, the App Intent.
9. On iOS: the Safari Web Extension.

## 9. Testable behaviors

- TRK-1. With no events, a 10 minute run under a fake clock writes exactly 20 samples.
- TRK-2. Idle verdicts follow 2.4 step 1 and 2.5, including the `passive_limit` cutoff and audio-only apps never being passive.
- TRK-3. Without a terminal adapter, the fallback picks the tty with the most recent input and `terminal` reports `fallback`.
- TRK-4. A matching pane title yields a file only while the pane's command is that editor.
- TRK-5. An editor RPC silent for 200 ms falls through to arguments, then cwd, within 100 ms plus the timeout.
- TRK-6. A `localhost:<port>` tab gets the item and group key of the pane that registered the port.
- TRK-7. A Safari URL without a `History.db` visit within 3 minutes becomes `safari (private)` and leaves the samples; Chromium incognito yields `<browser> (private)` with no URL.
- TRK-8. For each setting of 7.2, a matching fixture leaves no excluded path, domain, session, or title in any sample, log line, or `current.json`, through every entry point listed there.
- TRK-9. A block closes at its last active sample after `idle_close`; shorter idle gaps are not counted in `a`.
- TRK-10. Lock, sleep, display sleep, and a user switch close the block at the event time.
- TRK-11. No block has `s` and `e` on different dates; a block open at midnight ends at 00:00:00.
- TRK-12. 15 minutes on one group key then 15 on another splits within one tick of the change; two keys alternating every 2 minutes for 40 minutes never split.
- TRK-13. A block reaching `max_block` closes at the best change point in its last 30 minutes, or the current tick when there is none; a mostly passive one runs to `max_passive_block`.
- TRK-14. Summaries follow 2.7, and `a` never exceeds `e` minus `s`.
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
- TRK-28. Ladder minutes 1 to 20, a 10 minute gap, and minutes 21 to 30 yield two blocks of the iPhone split at the gap, with the set's label as context and group key.
- TRK-29. The `--replay` flag reproduces the expected file byte for byte and exits 0; a changed threshold makes it exit non-zero.
- TRK-30. The `--record` output contains no home path, host name, or URL path of the live run.
- TRK-31. The pane's dot, button, and setup marks follow 7.4 and update within 5 seconds; the agent is not registered until "Enable Tracker".
- TRK-32. The pane writes `settings.toml` only to create the default file when there is none (never over a hand-edited file, and never while an iCloud Drive placeholder stands for it) and to add a drafted exclusion, which changes nothing in the file but the one inserted value.
- TRK-33. The Full Disk Access row names the app by its bundle file name (`<APP_NAME>`, in Debug `<APP_NAME> Debug`) in its steps and its Finder button, which reveals the app bundle; the Accessibility row names and reveals `TimeTrackingAgent` (in Debug `TimeTrackingAgent Debug`).
- TRK-34. While the tracker is enabled and the Full Disk Access row is not ✓, the row offers "Restart Tracker", which restarts the agent once and re-reads the status; it is not offered otherwise.
- TRK-35. The "Open `<APP_NAME>` at login" row is ✓ when the app's login item is enabled; otherwise its action registers it, or opens Login Items when approval is required.
- TRK-36. The tmux snippet sets `focus-events` and has one hook line per hook of 3.1, each calling `tracker-event tmux <hook>` with its own hook name, which the agent accepts; the Claude Code snippet does the same for its three hooks; every call discards its output and exit status.
- TRK-37. "Ask for Access" on the Automation row asks for exactly the browsers and terminals the agent reads through Apple Events, skipping those that are not open, and the row then lists each open app's answer; before the first ask the row shows no such line.
- TRK-38. The first header of each block-log month file and detail-log day file carries `keys`, naming exactly the keys of that log's block lines with the labels of 4.2 and 4.3; later headers carry none.
- TRK-39. With `min_block` 10 minutes and `idle_close` 5 minutes: 4 minutes active, 6 idle, then 8 active give one block over all 18 minutes; 20 active, 7 idle, then 4 active and nothing more give one block of 31 minutes in place of the first; 4 minutes active alone gives no block; a short block is never merged across midnight; and in the logs the merged block's line replaces the previous one.
- TRK-40. With `min_block` 10 minutes: 15 minutes of Mac work, 5 minutes on the iPhone while the Mac is locked, and 15 more minutes of Mac work form one block with 30 minutes on the Mac and 5 on the iPhone; iPhone use during the Mac's attention is a secondary that adds nothing to `a`; overlapping iPhone and iPad use forms one block in which an iPad app wins its minutes over the iPhone's "Everything"; synced Safari history fills only time no iPhone stretch claims; a deleted block stays deleted when late iPhone events for its time arrive.

## 10. Decisions

- Command lines are never recorded: they can carry tokens.
- Only the block log and settings sync; live activity reaches other devices through `LiveState`.
- The agent is the only writer of the logs; rewrites go through its socket.
- Blocks split at midnight like entries, so per-day activity and tracked time cover the same interval.
- The multiplexer session drives splits; mapping to projects is the user's, in the Calendar.
- Every source with a permission, configuration, or undocumented format has a fallback; configuration is offered as snippets, never installed.
- Synced Safari history is off by default: weak attribution, and it duplicates the iOS extension, which outranks it (2.8).
- The block log is one timeline of the user: the iPhone and iPad fill the time away from the Mac rather than adding a parallel track.

Not included: Screen Time data from other devices; terminal adapters beyond WezTerm, iTerm2, and Terminal.app.

## 11. Interfaces

Provided, read through the shared library: the block log (4.2, every device), the detail log (4.3, recording Mac only), `current.json` (4.4: Timer, menu bar, Calendar and Activity open block, Tracker pane, `LiveStatePublisher`), the socket and `tracker-event` (7.3), `settings.toml` (7: agent, iOS collection, Tracker pane), the device-event merge (6.2), and the Tracker pane (7.4).

Assumed:

- From `spec_data_and_sync.md`: folder resolution, `ActivityReading` with `detail(for:)`, the block-log writer, `DeviceEventSource` and `DeviceEventSink`, the `DeviceEvent` record, `LiveState` and `LiveStatePublisher`.
- From `spec_architecture.md`: the agent bundle, registration with `KeepAlive`, entitlements, signing, the `tracker-event` target, container identifiers.
- From `spec_ios.md`: the collectors of 6.2 and exclusions read from `settings.toml`.
- From `spec_timer.md`: the settings window, the first-launch alert, idle detection reading `presence`.
- From `spec_calendar.md`: "Delete This Activity…" with confirmation.
