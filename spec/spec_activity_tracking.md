# Spec: Activity Tracking Component

## 1. Scope

The tracker records where the user's attention goes: in detail on the Mac, and with less detail on iPhone and iPad, as a record of each day in activity blocks ("blocks"). The Calendar and the Activity section show it (`spec_calendar.md`, `spec_activity.md`).

The tracker records raw identifiers (session names, paths, domains, app names) and never assigns a project, area, or client; the user does that when making entries from blocks in the Calendar. The tracker's records are separate from the app's time entries and projects, which it never reads or writes. It shows no UI of its own: it runs as the tracker agent, a login item (section 5), and its settings pane belongs to the Mac app (7.4). The iOS collectors are specified in `spec_ios.md`, the `DeviceEvent` record in `spec_data_and_sync.md`.

## 2. Design

### 2.1 Overview

Every 30 seconds, and at once when the user switches apps or tmux panes or locks the screen, the agent takes a *sample* of the Mac (2.3). A sample is a time, a presence state, and a set of *items*: while the user is present, exactly one primary item, and at any time any number of background items. The agent first decides whether the user is present, from keyboard and mouse input and the display state; while the user is away, the sample has only background items. Otherwise the agent reads what the frontmost window shows, through Accessibility and from the app itself (the terminal's focused pane and its tmux session, the browser's current tab, a window's document; section 3), and describes it as the sample's *primary item*: three strings from coarse to fine, the *context* (the app or terminal session, `tmux:paper`), the *subject* (the piece of work: a tmux window, a folder, a repository), and the *detail* (the thing in hand: a file, a page). The sample also lists *background items*: work that goes on without the user's attention, such as a busy coding agent or a running build, present or not. They never count as active time. Fixed rules derive each item's *workspace*: the tmux session, project folder, website, or app the work belongs to, the same whichever app shows it (2.2).

The iPhone and iPad allow no such access. The iOS app records coarser events (minutes of use of app groups the user labels, Safari tabs, automations, Focus changes), and the agent turns them into items of the same form (6.2).

The samples of all devices for one local day form one *timeline* (2.4). The agent cuts the timeline into *blocks*: a block ends when the user goes away, at midnight, or when the mix of workspaces changes (2.5). When a block closes, the agent adds up the seconds of each item and keeps the main items as the block's *summary*, named after its dominant workspace (2.6). Background work goes to the block whose time it falls in; work done while the user was away forms *background stretches* between the blocks, so the record shows what went on for a project even when nobody was at the Mac (2.7).

The tracker keeps four records (section 4):

- The block log: one line per block with its time range, active seconds, summary, background items, and dominant workspace, and one line per background stretch with its time range and background items (4.2). It is permanent and syncs through iCloud Drive, so every device's Calendar and Activity section show it. The Tracker pane calls these files the "activity logs".
- The detail log: per block, every item with its seconds, before the summary merges and cuts them (2.6), plus the timestamped browser visits, modified files, presence changes, and Safari dwell times within the block (4.3). It holds totals per item, not the samples, so when the samples expire, the order in which items had attention is gone. Permanent, and kept on the Mac that recorded it.
- The current state: the open block, the current primary item, presence, and the health of each source, rewritten on every sample for the Mac app (4.4).
- The samples: the raw material of the blocks and stretches, kept on the Mac for 90 days so that a day can be formed again (2.8).

Principles:

1. Attention, not activity. Presence comes from input and the display, never from what apps do: tabs reloading after a display wake are not attention.
2. One timeline of the user. Blocks never overlap. The iPhone and iPad fill the time the user spends away from the Mac rather than forming a parallel track.
3. Blocks are derived. A day's blocks and background stretches are formed again from its samples whenever input for that day arrives, so a late iPhone event changes the blocks as if it had arrived on time.
4. Privacy where data enters. Exclusions (7.2) apply before anything is written. Of what the tracker records, only the block log and the live activity the Mac app publishes (4.4) leave the Mac. Never recorded: keystrokes, clipboard, screenshots, message bodies, terminal command lines, password manager contents, and anything of a private browser window beyond the browser name.
5. Degrade instead of failing. Every source that depends on a permission, on configuration, or on an undocumented format has a fallback and reports its status (3.5).

### 2.2 Items and workspaces

The agent forms the items of each sample when it takes the sample (2.3 steps 3 and 4), from what it reads about the frontmost window. The app's bundle identifier picks the resolver: terminals (3.1), browsers (3.3), document apps, Finder, chat and meeting apps, and a generic one for every other app. An item that comes from an iPhone or iPad is formed by the Mac agent from the device's events (6.2). Every item carries the device it was observed on.

| Level | Meaning | Terminal | Browser | Document | Other app |
|---|---|---|---|---|---|
| context | The app, or the terminal session | `tmux:paper` | `safari` | `skim` | `mail` |
| subject | The piece of work | `draft` (tmux window) or `~/Documents/Papers/2026_Noise` (cwd) | `github.com/owner/repo` | `~/Documents/Papers/2026_Noise` | `Inbox` |
| detail | The thing in hand | `nvim notes.tex` | `pull/123` | `notes.pdf` | (none) |
| Read from | | The focused pane: its tmux session and window or its cwd, and its program, with an editor's open file (3.1) | The current tab's URL: host and repository, then the rest of the path (3.3) | The window's document (`AXDocument`): its work folder and file name | The app's name and the window title |

Background items have the same form: a coding agent session is `claude` with the session's name as subject, a running build is the pane's cwd with the program's name (3.1).

The context groups time by app in the Activity section. The workspace groups it by work, across apps: it decides where blocks split (2.5) and names the block. It is derived from the item by the first rule that applies:

1. A terminal pane in a tmux session: the session (`tmux:paper`). Without tmux: the work folder of the pane's cwd.
2. A notebook tab on `localhost`: the workspace of the pane that owns the port.
3. A file or folder: its work folder.
4. A URL on a code host: domain plus owner (`github.com/owner`). Any other URL: the bare domain.
5. Anything else: the app name.

A work folder is the nearest ancestor containing a `root_markers` entry (a Git repository by default), otherwise the folder `group_depth` levels below its watched root (`roots`), one level deeper below a `deep_folders` entry.

So a PDF of `~/Documents/Papers/2026_Noise` in Skim and Neovim in a plain terminal in that folder share one workspace, as do Safari and Chrome on `github.com/owner`, and switching between them never splits a block. In tmux, the session is the workspace, whatever folder its panes are in. Items from iPhone and iPad get their workspace by the rules of 6.2.

### 2.3 Samples

A tick takes a sample every 30 seconds. Events advance the tick, so that a change is timed when it happens rather than up to 30 seconds later: app activation, the tmux and Claude Code hooks (3.1), and the presence events lock, sleep, display sleep, and user switch (3.4), which are recorded in the sample.

A sample is taken in five steps:

1. Presence (3.4). The sample is not attentive, and steps 2 and 3 are skipped, when there was no input for `idle_after` and no passive item is frontmost or the display is off (`idle`), the screen is locked (`locked`), the Mac sleeps (`asleep`), or another user owns the console (`other_user`). Otherwise it is attentive: `active`, or `passive` by the rule below.
2. The frontmost app and its focused window through Accessibility (`AXTitle`, `AXDocument`, `AXURL` for browsers; no Screen Recording).
3. The primary item, by the app's bundle identifier: terminals by 3.1, browsers by 3.3. Chat apps give team and channel from the title. Meeting and screen-sharing apps give the meeting or host name. Document apps give `AXDocument`, else the title; Finder gives the front window's folder. Any other app gives its name plus the window title.
4. The background items, also while the user is away but not while the Mac sleeps: every busy coding agent session; every tmux client with input in the last 30 seconds in a session other than the primary item's; `job_commands` running in panes that are not active.
5. Apply the exclusions (7.2) and write the sample: time, state, primary item, background items, and debug fields (bundle identifier, filtered title, tmux target).

Passive attention: apps in `passive_apps`, tabs on `passive_domains`, and meeting and screen-sharing apps count as attention while frontmost with the display on, even without input, up to `passive_limit`; such samples are `passive`. Audio-only apps never count.

### 2.4 The timeline

Blocks are formed from one timeline per local day, which merges everything recorded for that day:

- The Mac's samples, live (2.3) or reconstructed from the Knowledge store (3.2), claim the time they cover.
- The stretches of the iPhone and iPad (6.2) and of synced Safari history (6.1) fill the rest, as one sample every 30 seconds. Where they overlap, the most specific wins: the iOS app, then automations, web extension tabs, named ladder sets, "Everything", and synced Safari history last; on a tie the later start.
- Another device's stretch during the Mac's attention becomes a background item of that time (2.7), so it is listed with the block and adds nothing to its active time.
- Within another device's stretch, the Mac's samples that are not attentive, and its lock and sleep events, are dropped, so a block runs on from the Mac to the iPhone and back. The split test still separates them where the workspaces differ.

### 2.5 Blocks

The agent reads the timeline in time order. Each attentive sample is credited with the time up to the next sample, at most 60 seconds, when that sample is attentive or an event that closes the block; otherwise it is credited nothing. The credit goes to the sample's primary item; background items are credited on their own (2.7).

An attentive sample opens a block when none is open. The open block takes every following attentive sample until it closes on the first of these:

- `idle_close` without an attentive sample: it ends at its last attentive sample. Shorter gaps are absorbed: they lie inside the block but add no credited time.
- Lock, sleep, display sleep, or a user switch: it ends at the event's time, unless another device's use covers it (2.4).
- Local midnight: it ends at 00:00, and the next attentive sample opens a new block, so no block spans two dates.
- A split, by the split test.
- Reaching `max_block` (`max_passive_block` when mostly passive) without a split: it ends at the best change point in its last 30 minutes, or at the current sample when there is none, and the rest stays open as a new block.

The split test runs after every sample once the open block is longer than `split_after`. The candidates are the change points, where the credited time moves from one workspace to another, with at least `min_half` of credited time on each side. For each candidate, the two sides are compared as shares of their credited time per workspace, by weighted Jaccard distance: 1 minus the sum over workspaces of the smaller share divided by the sum of the larger share (0 for the same mix, 1 for no workspace in common). The candidate with the largest distance (the earliest on a tie) is the best change point. If it reaches `split_threshold`, the part before it closes as a block, and the rest stays open. So moving from one workspace to another splits at the move, while alternating between two never does, because both sides hold the same mix.

No block is shorter than `min_block` (from start to end). A block that closes shorter is held back, unwritten, with a merge window of `idle_close` plus its own length:

1. An attentive sample within the window after its end reopens it: it continues as the open block, and the gap is absorbed (across a lock or sleep too).
2. Otherwise, once the window has passed, it merges into the previous block when that ended within the window before its start, on the same date, and the two together stay within `max_block` (`max_passive_block` when mostly passive). The merged block keeps the previous block's start and replaces it in both logs.
3. Otherwise it is dropped.

Nothing merges across midnight, a Focus that suspends collection, or agent shutdown.

### 2.6 The block summary

When a block closes:

1. Sum the credited seconds per primary item and device.
2. Merge items of one device sharing context and subject when their details would take more than three lines (`nvim draft (5 files)`).
3. Drop items under `summary_min_share` and under 60 seconds, but keep the top item of every workspace present for at least 3 minutes.
4. Order by time, cap at `summary_lines`.
5. Store the dominant workspace and its share.
6. Store the active seconds per device, most first, and the seconds reconstructed from the Knowledge store.
7. Append the background items with at least 5 minutes within the block's range (2.7).

```
09:10-09:44  tmux:paper (71%)  tmux:paper nvim draft (3 files) 18m · safari github.com/owner/repo pull/123 9m · mail Inbox 4m  + claude refactor-parser (busy 12m)
```

### 2.7 Background work

Background items are credited by time, apart from the blocks: every Mac sample, attentive or not, credits each of its background items with the time up to the next Mac sample, at most 60 seconds, and another device's use during the Mac's attention counts for the time it covers (2.4). Time within a block's range goes to that block, which lists every background item with at least 5 minutes there, including time in the idle gaps the block absorbed.

The rest is background work while the user was away, and forms *background stretches*. A gap of `idle_close` or more without background time, a block, or local midnight separates two stretches. A stretch lists its background items with at least 5 minutes and spans the time of those items; without such an item it is not recorded. Today's last stretch is recorded once `idle_close` has passed without background work.

A stretch is not a block: it has no active time and no workspace, it never overlaps a block, and the time it covers still counts as away (`spec_activity.md`).

```
12:10-12:48  (away)  + claude refactor-parser (busy 38m)
```

### 2.8 Forming a day again

The agent stores what a day's timeline is made of for 90 days (4.1): the samples, the samples reconstructed from the Knowledge store, the synced Safari visits with their attributed device, and the iPhone and iPad events. It forms today's blocks and background stretches again on every tick, and a past day's whenever an input for that day arrives (iPhone events through iCloud, a Knowledge reconstruction, synced Safari history), and replaces the day's lines in the block log and its detail file when they changed. Today's last block may still be open; `current.json` shows it (4.4). The agent keeps the last day it formed in `samples.sqlite`; on its first tick on a later day (after midnight, or after it was not running), it first forms every day since then, so a block still open when it stopped closes on its own day. On SIGTERM (logout, shutdown, unregistration) it forms today once more with the open block closed, then exits. A past day's last block closes at its last attentive sample, or at midnight. A new or changed block's detail keeps the URLs, files, presence transitions, and dwell times of the day's old detail lines within its range.

## 3. Sources

### 3.1 Terminal

The focused pane's tty comes from a terminal adapter (WezTerm through `wezterm cli`, iTerm2 and Terminal.app through AppleScript; kitty optional). Without one, it is the tty of the frontmost terminal's descendant processes with the most recent input (tmux `client_activity`, else the tty's access time). A tmux client on that tty (on every server socket under `$TMUX_TMPDIR` or `/tmp/tmux-<uid>/`) gives the session and the active pane's window name, command, cwd, title, and pid; without tmux, the tty's foreground process and its cwd.

The pane's foreground program refines the item:

- Editors: the pane title matched against `title_patterns`, trusted only while the pane's command is that editor; then editor RPC (Neovim: the socket of the `nvim --embed` descendant, `expand("%:p")`, 200 ms timeout, cached per pane); then process arguments; then cwd. While the title works, RPC cross-checks it every 10 minutes per pane and reports a mismatch to health.
- Coding agents, recognized by executable path or title: for Claude Code, `~/.claude/sessions/<pid>.json` gives session name, cwd, tmux target, and busy or idle status; transcripts are never read live, and never under `private_agent_paths`. Other `agent_processes` give process name plus cwd.
- Interpreters (Julia, Python, R, Node): cwd as subject, command as detail. A notebook server's listening port is registered so a browser tab on it inherits the pane's item.
- Shells: the cwd only.
- Commands in `job_commands`: cwd plus program name.

The tmux hooks `client-session-changed`, `after-select-window`, `after-select-pane`, and `client-focus-in` (the terminal window gains focus; it needs `set -g focus-events on`), and the Claude Code hooks `UserPromptSubmit`, `Stop`, and `SessionEnd`, may call `tracker-event tmux <hook>` and `tracker-event agent <hook>`, which write one line to the agent's socket and advance the tick. The event needs the hook's name; `tracker-event tmux` alone is rejected. The snippets of 7.4 run the tool in the background (`run-shell -b`, `&`) and discard its output and exit status, so neither a stopped tracker nor the tick it waits for (over a second) holds up tmux or Claude Code, which cancels `SessionEnd` hooks after 1.5 seconds. The sources `tmux_events` and `agent_events` are `active` when such an event arrived in the last 7 days, which the Setup rows show.

### 3.2 Knowledge store

The macOS Knowledge store (`~/Library/Application Support/Knowledge/knowledgeC.db`, Full Disk Access) records app intervals (`/app/usage`), Safari dwell time (`/app/webUsage`), and display state (`/display/isBacklit`). The agent reads a copy of the database and its WAL, and sets the source `off` when the schema is not the expected one. At agent start and every 15 minutes it reconstructs samples for periods the agent was down (one per 30 seconds of each app interval, counted in `rec`, 4.2) and adds Safari dwell times to the detail log; once a day it cross-checks the agent's app timeline.

### 3.3 Browsers

The active tab of a frontmost browser is read through Apple Events: Safari's current tab `URL` and `name`; for Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi) `URL`, `title`, and the incognito flag, skipping private tabs. Browsers without a scripting dictionary, or with Automation denied, give `AXURL` plus title, and "Private Browsing" in the title marks a private window.

Safari private windows write no history: a sampled Safari URL with no visit in a copy of `History.db` within 3 minutes is recorded as `safari (private)` and the sampled URL is dropped. Without Full Disk Access, Safari URLs are reduced to the domain.

At block close, the detail log gets every visit in the block's range from Safari's `History.db` (`origin = 0`) and each Chromium profile's `History` (copies, never the live files).

Block summaries strip query and fragment except on a short allowlist (code host pull request and issue paths, forum topic ids, arXiv ids), map `localhost:<port>` to the owning pane's item, and reduce domains in the `summary_domain_only` categories to the domain. The detail log keeps full URLs, apart from private domains.

### 3.4 Presence and files

Idle seconds come from `CGEventSource` (no permission); lock from `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`; display sleep, system sleep, and user switches from `NSWorkspace` notifications; console ownership is checked each tick.

An FSEvents stream on `roots`, skipping `prune_names`, records modified files into the detail log of the block. When a block's terminal items have no resolved file, files modified in the pane's cwd fill the detail.

### 3.5 Health and fallbacks

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

## 4. Storage

### 4.1 Tiers and folders

| Tier | Where | Content | Retention |
|---|---|---|---|
| Samples | Agent folder, `samples.sqlite` (GRDB) | One row per sample; reconstructed samples, synced Safari visits, iPhone and iPad events, and deleted time (2.8, 7.3) | 90 days |
| Block log | Shared folder, `blocks/<mac>/YYYY-MM.jsonl` | One line per closed block and per background stretch | Permanent |
| Detail log | Agent folder, `Activity/detail/YYYY-MM-DD.jsonl` | Per block: all items, URLs, modified files, presence transitions | Permanent |
| Current state | Agent folder, `Activity/current.json` | Open block, primary item, presence, health | Each tick |
| Settings | Shared folder, `settings.toml` | Section 7 | Permanent |

The agent folder is `<App Group container>/Library/Application Support/TimeTracking/` (`spec_architecture.md`); it also holds the socket `tracker.sock` and the health watchdog file, and nothing in it leaves the Mac. The shared folder is `Activity/` in the product's iCloud Drive container, outside `Documents/`, and holds only `blocks/` and `settings.toml`. Each Mac's agent writes only its own subfolder of `blocks/`, named by the Mac's hardware UUID (which stays when the Mac is renamed), so no two Macs ever rewrite the same file and iCloud Drive never has to choose between two versions; readers read every subfolder. Month files directly in `blocks/` come from before the subfolders: readers still read them, and on start each agent moves the lines that follow a header whose `dev` is its own name into its subfolder, leaves another Mac's lines, and removes a file left without blocks or stretches. Every block-log, detail-log, and `current.json` write replaces the whole file (a temporary file, then a rename), so a reader sees a day as it was before or after a rewrite, never in between; when a day changes, its detail file is replaced before its month file. Without iCloud Drive, the agent folder's `Activity/` takes its place (`shared_folder` reports `off`).

At start, the agent checks that it can write the container. If it cannot, it writes `blocks/` and reads `settings.toml` in the agent folder's `Activity/`, and `shared_folder` reports `fallback`; the Mac app then copies each changed month file into the container at the same path below `blocks/` (whole-file replace, `NSFileCoordinator`) and keeps the two `settings.toml` identical (newer modification time wins). The status alone tells the Mac app to copy: `shared_folder` reports `fallback` only in this case, and the reason is display text that nothing compares.

### 4.2 Block log format

```json
{"type":"header","format":1,"tz":"-04:00","dev":"macbook","contexts":{"tmux:paper":"com.github.wez.wezterm","safari":"com.apple.Safari","Mail":"ladder","claude":"claude"},"keys":{"s":"start (local time)","e":"end (local time)","a":"active seconds","dev":"devices [device, active seconds]","rec":"seconds reconstructed from the Mac's app usage history","g":"dominant workspace","gs":"share of the dominant workspace","items":"items [context, subject, detail, seconds, device]","bg":"background items [context, subject, detail, seconds, device]"}}
{"s":"2026-10-28T09:10:00","e":"2026-10-28T09:44:30","a":1860,"dev":[["macbook",1620],["iPhone",240]],"rec":0,"g":"tmux:paper","gs":0.71,"items":[["tmux:paper","draft","nvim (3 files)",1080,"macbook"],["safari","github.com/owner/repo","pull/123",540,"macbook"],["Mail","Mail","",240,"iPhone"]],"bg":[["claude","refactor-parser","",720,"macbook"]]}
{"type":"background","s":"2026-10-28T12:10:00","e":"2026-10-28T12:48:30","bg":[["claude","refactor-parser","",2280,"macbook"]]}
```

Each month file starts with a header object; another header follows a time zone change and precedes the first block using a context not yet in `contexts`, which maps context keys to bundle identifiers (or process names). The block keys are short to keep lines short, so the first header of each month file also carries `keys`, a legend mapping each block key to a human-readable label (the labels of the example); later headers leave it out, and readers ignore it. Readers skip objects with a `type` other than `header` and `background`, and ignore unknown keys. The header's `dev` names the Mac that wrote the file.

In a block, `s` and `e` are local times on one date, and `s` identifies the block (no two blocks share time). `a` is the active seconds, the sum of credited item seconds before the summary cut (less than `e` minus `s` when idle gaps were absorbed). `dev` lists `[device, active seconds]` for each device the block spent time on, most first, where a device is the Mac's name, an iPhone's or iPad's, or `remote` for unattributed synced Safari history (6.1). `rec` is the part of `a` reconstructed from the Knowledge store (3.2). `g` and `gs` are the dominant workspace and its share of `a`. `items` and `bg` (the background items) hold `[context, subject, detail, seconds, device]`, with `""` for no detail. Idle time is the absence of a block.

A background stretch (2.7) is a line with `type` `background`, its local `s` and `e` on one date, and `bg` as in a block; the month's lines are in time order. A header precedes a stretch that uses a context not yet in `contexts`, as it does a block. Readers written before stretches existed skip these lines.

### 4.3 Detail log format

One file per local date, headers as in 4.2. A block line with `items` uncut, plus `urls` as `[time, browser, url, title]`, `files` as `[time, path]`, `presence` as the state transitions in and around the block, so every gap between blocks is covered, and `dwell` as Safari dwell times `[time, url, seconds]` from the Knowledge store (3.2) when there are any. The legend `keys` of the first header also labels these: `urls` "URL visits [time, browser, URL, title]", `files` "modified files [time, path]", `presence` "presence transitions [time, state]", `dwell` "Safari dwell times [time, URL, seconds]". The library reads it on the recording Mac only (`detail(for:)`, `spec_data_and_sync.md`).

### 4.4 Current state

Rewritten atomically (temporary file, then rename) on every tick and presence event; never copied to the shared folder.

```json
{"format":1,"dev":"macbook","block":{"s":"2026-10-28T09:10:00","a":1080,"dev":[["macbook",1080]],"rec":0,"g":"tmux:paper","gs":0.71,"items":[["tmux:paper","draft","nvim (3 files)",1080,"macbook"]],"bg":[]},"primary":["tmux:paper","draft","nvim notes.tex"],"presence":{"state":"active","since":"2026-10-28T09:10:00","last_input":"2026-10-28T09:44:27"},"health":{"last_tick":"2026-10-28T09:44:30","version":"1.0 (42)","sources":[{"id":"terminal","name":"Terminal tab","status":"active","reason":""},{"id":"browser","name":"Browser tab","status":"active","reason":""},{"id":"knowledge","name":"App usage history","status":"off","reason":"Full Disk Access is off; macOS app usage history can't be read"}]}}
```

The `block` is today's open block (2.8) summarized as of now, with the keys of 4.2 but without `e` (or `null`); `primary` is `null` while the user is not attentive; `presence.state` is the presence state (2.3), and `since` is the time of the event or input that set it, not of the tick that noticed it; `health.sources` lists every source of 3.5.

Every reader derives the tracker's liveness from `health.last_tick` by one rule: the tracker is running while the last tick is younger than 2 minutes, and not running when it is 2 minutes old or older or `current.json` is missing. While running, a last tick of 90 seconds or older counts as delayed. The Tracker pane (7.4), the Activity footer, the menu bar warning, the Timer's idle detection, and `agentRunning` in `LiveState` all use this rule.

The agent pushes nothing. The Timer reads `presence` for its own idle detection (`spec_timer.md`). The Mac app's `LiveStatePublisher` copies the tracker fields of this Mac into `LiveState` (fields and rules in `spec_data_and_sync.md`); they are already filtered by the exclusions.

## 5. Agent

The agent, `TimeTrackingAgent.app`, is a headless login item with `KeepAlive` (bundle, registration, entitlements in `spec_architecture.md`), always team-signed because TCC keys grants to signing identities. Its modules: Presence, Focus, Resolvers (adapters per app), Settings (loads and reloads `settings.toml`), Sampler, Blocker (blocks, summaries, logs, `current.json`), Knowledge, History, Devices (6.2), Events (the socket), and Health. A tick takes under 100 ms.

| Flag | Effect |
|---|---|
| `--record <folder>` | Writes adapter outputs and the run's samples as fixtures, with home-directory paths, host names, and URL paths replaced by placeholders |
| `--replay <fixture>` | Runs the Blocker over a recorded sample stream, compares with `<fixture>.expected.jsonl`, exits non-zero on a difference |
| `--unregister` | Removes the login item registration and exits |

| Permission | Granted to | Gives |
|---|---|---|
| Accessibility (required) | `TimeTrackingAgent.app` | Window titles, documents, browser addresses (2.3) |
| Automation, per browser and scriptable terminal | The app | The browser's tab (3.3) and the terminal's front tab (3.1); macOS asks at first use, or on "Ask for Access" (7.4) |
| Full Disk Access (optional) | The app | The Knowledge store (3.2), Safari's history and synced tabs (3.3, 6.1) |

macOS checks Accessibility for the agent itself, but attributes the agent's file access and Apple Events to its responsible app, the one `AssociatedBundleIdentifiers` names (`spec_architecture.md` §1.4): `<APP_NAME>.app`, in Debug `<APP_NAME> Debug.app`. The app therefore carries the Apple Events entitlement and `NSAppleEventsUsageDescription` as well as the agent; without them macOS refuses the agent's Apple Events with `-1743` and never asks. A new Full Disk Access grant reaches the running agent only after a restart, so the Tracker pane offers "Restart Tracker" (7.4).

## 6. Other Apple devices

### 6.1 Synced Safari history

With `synced_safari_history` on, the History module stores Safari's `History.db` visits with `origin = 1` (synced from other devices) for the timeline (2.4): a visit lasts until the next one when that follows within 5 minutes. A run of visits without a longer gap belongs to `remote`, unless `CloudTabs.db` (polled every 5 minutes) shows that within it exactly one device's tab set changed to include a visited URL; then to that device's name.

### 6.2 Collected by the iOS app

The iOS app writes raw, labeled `DeviceEvent` records per device, exclusions applied, with these `source` values:

| Source | Mechanism | Gives |
|---|---|---|
| `ladder` | DeviceActivity: a monitor extension receives `eventDidReachThreshold` at 1, 2, 3, … minutes of daily use of each user-labeled set of apps, categories, or domains ("Everything", "Mail"), schedule midnight to midnight | Minutes of use per set |
| `focus` | Focus filter | Focus on and off |
| `intent` | App Intent "Log activity event" for Shortcuts automations | Exact times with a label |
| `webext` | Safari Web Extension, tab activations and URL changes | Browser items |
| `app` | The iOS app's foreground transitions | App use |

The cap on monitored events is undocumented; the iOS app measures it and sets the ladder steps from it (`spec_ios.md` §9.2).

The Devices module turns each device-day's events into stretches of the timeline (2.4) on the device's name:

- A counted ladder minute covers the minutes since the set's previous counted step, with the set's label as context, subject, and workspace; "Everything" (any app) is recorded with the device's name as context and workspace, without a subject.
- A web extension tab covers up to a minute, until the next tab, as a browser item under the rules of 3.3.
- An automation covers a minute, or from `appOpened` to `appClosed`, with its label.
- The app covers the time from its foreground to its background.

A Focus that suspends collection closes the open block.

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
# Long-running commands recorded as background items.
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

Settings changes never touch past logs. Three socket commands rewrite the log files and samples they touch: `delete-block <s>`, `forget-day <date>`, and `reapply-exclusions <from> <to>`. `delete-block` and `forget-day` delete what the block or day was formed from (samples, reconstructed samples, synced Safari visits, iPhone and iPad events) and record the time as deleted, so late events never form a block there again; then the day is formed again (2.8), which removes the background stretches of that time too. `reapply-exclusions` applies to the items of background stretches as to blocks and drops a stretch left without items. The agent rewrites, replacing each file atomically and keeping unaffected lines byte-identical; the answer is `ok` or `error <reason>`. The UI for `delete-block` is "Delete This Activity…" in the Calendar's activity column (`spec_calendar.md`); the other two are run with `tracker-event`, which the Tracker pane's "Activity logs" info shows. The reasons are protocol text; the Mac app logs them and shows its own sentence: "The tracker could not be reached." (no socket, or the link to it fails), "The tracker is not running." (nothing listens), "This activity is no longer in the logs." (a reason starting with `no block at`), "The tracker is restarting. Try again in a moment." (`the tracker is stopping`), and "The tracker could not change the logs." for any other.

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
| Claude Code hooks (optional) | `agent_events` | Start and stop of work are recorded the moment they happen / noticed within 30 seconds | Copy Snippet (the hooks JSON, each command `tracker-event agent <hook> >/dev/null 2>&1 &`). Info: add to `~/.claude/settings.json`, merging into an existing `hooks` key |

"Restart Tracker" restarts the agent (`launchctl kickstart -k` of its label, run by the app), then re-reads the status; when it fails, the status section reads "The tracker could not be restarted. Disable and enable it to try again." and the exit status goes to the log. "Ask for Access" asks macOS, one app after another, whether `<APP_NAME>` may control each browser of 3.3 and terminal of 3.1 that the tracker reads through Apple Events and that is open (`AEDeterminePermissionToAutomateTarget`, which shows the prompt where there is no answer yet). One line under the buttons then gives the answers by the names the apps show: "Allowed: Safari and iTerm2.", "Declined: Google Chrome; turn it on in System Settings.", "Couldn't ask: `<names>`.", or "None of the browsers and terminals the tracker asks are open." The library holds the list of apps (`AutomationTargets`), which equals the scriptable entries of the agent's browser and terminal tables. The row's mark still comes from the tracker's health. Under `-UITesting` nothing real is asked.

"Copy Snippet" and the popover's "Copy" put the snippet on the pasteboard and read "Copied" with a checkmark for 2 seconds, at the width of the longer title.

Recording. Each source's name on screen (3.5) and its status: "On" in the secondary color, "Limited: `<reason>`" or "Off: `<reason>`" in the warning color; "The tracker hasn't reported yet." before the first `current.json`.

Exclude from Tracking. Shown only when the Activity section opened the pane with a draft (`showTrackerSettings(exclusion:)`): the list's entry name ("App (bundle identifier)", "tmux session", "Site (domain)") with a focused field holding the drafted value, and "Cancel" and "Add to Settings File" (default); the footer reads "Adds the entry to the `<list>` in the settings file, which keeps everything else as it is." Adding inserts the value into its list in `[privacy]` (7.1) and confirms under the settings file: "Added `<value>` to the `<list>`." A list is named on screen with its key in parentheses, for finding it in the file: "excluded apps (exclude_apps)", "apps recorded by name only (name_only_apps)", "excluded sites (exclude_domains)", "private sites (private_domains)", "excluded folders (exclude_paths)", "private coding agent folders (private_agent_paths)", "excluded tmux sessions (exclude_tmux_sessions)", "excluded keywords (exclude_keywords)", "excluded title keywords (exclude_title_keywords)".

Under the settings file, a file that does not decode reads "The settings file has an error on line `<n>`: `<description>`. Fix it in the editor." (TOML syntax) or "In the settings file, `<table.key>` can't be used: …" (a wrong value); a list that is not an array reads "In the settings file, exclude_apps under [privacy] must be a list, like ["com.example.app"]."; a failed write reads "Couldn't write the settings file: `<reason>`". Without the App Group container both paths read "Not available".

Files. "Settings file": the path of `settings.toml` (`~` for the home folder, selectable, truncated in the middle), "Open in Editor" (the app the user chose for `.toml` files, else TextEdit) and "Show in Finder", which opens the folder holding the file; both first create the default file when there is none. "Activity logs": the path of `blocks/`, "Show in Finder" (opens `blocks/`; disabled until the folder exists), and an info button with the maintenance commands: `tracker-event forget-day <date>` and `tracker-event reapply-exclusions <from> <to>` (7.3), with today's date in the examples. The section footer says that exclusions, watched folders, the idle threshold, and site categories are set in the file, each with a comment, and that the tracker picks up a change within 30 seconds.

The pane has no editors for exclusions or options and no maintenance controls: the file is where settings are changed, and rewriting logs is a command-line task.
## 8. Testable behaviors

- TRK-1. With no events, a 10 minute run under a fake clock writes exactly 20 samples.
- TRK-2. Presence verdicts follow 2.3, including the `passive_limit` cutoff and audio-only apps never being passive.
- TRK-3. Without a terminal adapter, the fallback picks the tty with the most recent input and `terminal` reports `fallback`.
- TRK-4. A matching pane title yields a file only while the pane's command is that editor.
- TRK-5. An editor RPC silent for 200 ms falls through to arguments, then cwd, within 100 ms plus the timeout.
- TRK-6. A `localhost:<port>` tab gets the item and workspace of the pane that registered the port.
- TRK-7. A Safari URL without a `History.db` visit within 3 minutes becomes `safari (private)` and leaves the samples; Chromium incognito yields `<browser> (private)` with no URL.
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

## 9. Decisions

- Command lines are never recorded: they can carry tokens.
- Only the block log and settings sync; live activity reaches other devices through `LiveState`.
- The agent is the only writer of the logs; rewrites go through its socket.
- Blocks split at midnight like entries, so per-day activity and tracked time cover the same interval.
- In a terminal, the tmux session is the workspace, not the folder: a session often holds panes in several folders of one piece of work.
- Configuration of other programs (Neovim, tmux, Claude Code) is offered as snippets, never installed.
- Synced Safari history is off by default: weak attribution, and it duplicates the iOS extension, which outranks it (2.4).
- Background work while the user is away is recorded as background stretches beside the blocks, not as blocks: a block measures attention, and the time between blocks stays away time, while the stretches still tell what went on for a project.

Not included: Screen Time data from other devices; terminal adapters beyond WezTerm, iTerm2, and Terminal.app.

## 10. Interfaces

Provided, read through the shared library: the block log with its background stretches (4.2, every device), the detail log (4.3, recording Mac only), `current.json` (4.4: Timer, menu bar, Calendar and Activity open block, Tracker pane, `LiveStatePublisher`), the socket and `tracker-event` (7.3), `settings.toml` (7: agent, iOS collection, Tracker pane), the device-event merge (6.2), and the Tracker pane (7.4).

Assumed:

- From `spec_data_and_sync.md`: folder resolution, `ActivityReading` with `detail(for:)`, the block-log writer, `DeviceEventSource` and `DeviceEventSink`, the `DeviceEvent` record, `LiveState` and `LiveStatePublisher`.
- From `spec_architecture.md`: the agent bundle, registration with `KeepAlive`, entitlements, signing, the `tracker-event` target, container identifiers.
- From `spec_ios.md`: the collectors of 6.2 and exclusions read from `settings.toml`.
- From `spec_timer.md`: the settings window, the first-launch alert, idle detection reading `presence`.
- From `spec_calendar.md`: "Delete This Activity…" with confirmation.
