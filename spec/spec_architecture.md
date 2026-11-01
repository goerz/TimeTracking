# Spec: Project Architecture and Build System

This spec defines the Xcode project and its targets, the shared library, identifiers and entitlements, the APNs credentials, the Makefile, the testing rules, code conventions, dependencies, and the implementation order. The product name in code is `TimeTracking`; the name the user sees is a personal build setting (2.1).

Toolchain: macOS 27, Xcode 27, Swift 6, deployment targets macOS 27.0 and iOS 27.0. A paid Apple Developer Program membership is required. The apps are installed from Xcode or the Makefile only; there is no App Store, TestFlight, or Developer ID distribution.

## 1. Targets and the shared library

### 1.1 Targets

One Xcode project, `TimeTracking.xcodeproj`, plus one local Swift package, `Packages/TimeTrackingCore`, linked statically by every executable (no `Contents/Frameworks/`, no rpath). There is no workspace.

| Target | Kind | Product | Bundle identifier | Spec |
|---|---|---|---|---|
| `TimeTrackingCore` | Swift package library (macOS, iOS) | `TimeTrackingCore` module | (none) | `spec_data_and_sync.md` |
| `TimeTracking` | Mac app | `<APP_NAME>.app` (Debug: `<APP_NAME> Debug.app`), module `TimeTracking` | `<APP_ID>` | `spec_timer_window.md`, `spec_menubar.md`, `spec_calendar.md`, `spec_reports.md`, `spec_projects.md`, `spec_activity.md` |
| `TimeTrackingAgent` | Mac login item (helper app) | `TimeTrackingAgent.app` (Debug: `TimeTrackingAgent Debug.app`) at `Contents/Library/LoginItems/` | `<APP_ID>.agent` | `spec_activity_tracking.md` |
| `TimeTrackingCLI` | Mac command-line tool | `timetracking` at `Contents/Helpers/` | (none) | `spec_automation.md` |
| `TrackerEvent` | Mac command-line tool | `tracker-event` at `Contents/Helpers/` | (none) | `spec_activity_tracking.md` |
| `TimeTrackingiOS` | iOS app (iPhone and iPad) | `<APP_NAME>.app`, module `TimeTrackingiOS` | `<APP_ID>` | `spec_ios.md` |
| `TimeTrackingWidgets` | Widget extension (widgets, controls) | `TimeTrackingWidgets.appex` | `<APP_ID>.widgets` | `spec_ios.md` |
| `TimeTrackingIntents` | App Intents extension (Focus filter, log-activity-event intent) | `TimeTrackingIntents.appex` | `<APP_ID>.intents` | `spec_ios.md` |
| `TimeTrackingMonitor` | DeviceActivity monitor extension | `TimeTrackingMonitor.appex` | `<APP_ID>.monitor` | `spec_ios.md` |
| `TimeTrackingWebExtension` | Safari web extension | `TimeTrackingWebExtension.appex` | `<APP_ID>.web-extension` | `spec_ios.md` |

Test bundles: `TimeTrackingCoreTests` (package), `TimeTrackingTests` (Mac view models), `TimeTrackingUITests` (Mac), `TimeTrackingiOSTests` (iOS view models), `TimeTrackingiOSUITests` (iPhone and iPad), `TimeTrackingAgentTests`, `TimeTrackingCLITests`. There is no Mac widget and no Apple Watch target.

### 1.2 The library

One Swift target with these folders:

| Folder | Contents |
|---|---|
| `Model/` | Entities, typed ids, durations, date ranges, area colors (`#RRGGBB`, default-color rule, display derivations) |
| `Store/` | SQLite schema and migrations, the store actor and write API with the invariant pass, the outbox, the `entries` view, the Darwin change notification |
| `Sync/` | The `CKSyncEngine` coordinator, `SyncTransport` (CloudKit and in-memory), conflict rules, `LiveState`, `LiveStatePublisher`, the `Device` record |
| `Push/` | The APNs client (2.4) and the data spec's `WidgetPushSender` (macOS only) |
| `Queries/` | Entries by day, reports, structure queries, autocompletion, the running entry, `StoreObserver` |
| `Interchange/` | JSON export and import, the CSV writers |
| `Activity/` | `FileActivityStore`, folder resolution, the `settings.toml` model, the block log writer, `DeviceEventSink`, `DeviceEventSource` |
| `TimeBlocks/` | The time-block calendar in EventKit and the project link (`spec_calendar.md`) |
| `Suggestions/` | The project suggestion engine (`spec_calendar.md`) |
| `Intents/` | App Intents, entities, `AppIntentsPackage`, the shared App Shortcut phrase table |
| `Support/` | `Clock` and `ManualClock`, `LaunchArguments`, `AppIdentity` (App Group, CloudKit container, URL scheme from the Info.plist), logging |

The library never imports SwiftUI, AppKit, UIKit, or WidgetKit. Observed types are `@MainActor @Observable`; the store and sync coordinator are actors; model values are `Sendable` structs.

### 1.3 What each target holds

User interface targets hold views, view state, and platform glue only. A view model may hold selection, drafts, sort order, and presentation state and call the library; it may not compute totals, overlaps, or export formats. If a view model test needs a store fixture, the logic belongs in the library.

| Target | Holds |
|---|---|
| `TimeTracking/` | Scenes (the main window and the Mini Timer), Timer, the sections, status item, settings window (with the Tracker pane), agent registration (1.4), global shortcuts, AppKit glue (4.2), URL handler, and the live-update side: it runs `LiveStatePublisher` and `WidgetPushSender` |
| `TimeTrackingiOS/` | Scenes, Timer tab, iPad tabs, background refresh and silent-push handlers, widget push token upload, URL handler |
| `Shared/` | Views compiled into both apps (picker, project dialog, entry row and editor, task field, color swatch, Pomodoro ring, report chart and tree, calendar columns); platform differences are `#if os(macOS)` around a modifier |
| `AppResources/` | The app icon (`AppIcon.icon`) and the `AccentColor` asset, in the Mac app, the agent, and the iOS app (`spec_design.md` §9) |
| `TimeTrackingAgent/` | The tracker (`spec_activity_tracking.md`); links the library and GRDB; `LSUIElement`; flags `--record <folder>`, `--replay <file>`, `--unregister` |
| `TrackerEvent/` | Connects to the agent's socket, writes one line, exits; links only Foundation |
| `TimeTrackingCLI/` | Argument parsing and output formatting; everything else through the library; never touches CloudKit |
| iOS extensions | Rendering and forwarding only (`spec_ios.md`) |

### 1.4 The agent as a login item

The agent is embedded at `Contents/Library/LoginItems/TimeTrackingAgent.app` and registered with `SMAppService.agent(plistName: "<APP_ID>.agent.plist")`. A build phase generates that plist into `Contents/Library/LaunchAgents/`: `Label` and the Mach service are the agent's bundle identifier, `BundleProgram` is `Contents/Library/LoginItems/TimeTrackingAgent.app/Contents/MacOS/TimeTrackingAgent` (in Debug `TimeTrackingAgent Debug.app`, 2.2), `AssociatedBundleIdentifiers` names the app, `KeepAlive` is true, `ProcessType` is `Background`.

The agent is unsandboxed with the hardened runtime and always signed with the team's development certificate, because TCC keys Accessibility and Full Disk Access grants to the signing identity. Through `AssociatedBundleIdentifiers` the app is the agent's responsible process: macOS checks the agent's Full Disk Access against the app's grant, while Accessibility is checked for the agent itself (`spec_activity_tracking.md` §5, §7.4).

The Mac app registers the agent only when the user clicks "Enable Tracker" in the settings window's Tracker pane; the first-launch alert offers to open that pane (`spec_timer_window.md` §8.2). The Debug app registers the Debug agent (`<BUNDLE_ID>.debug.agent`), so a development build never replaces the recording agent.

### 1.5 Identifiers and containers

Every identifier derives from `TT_APP_ID`, so a Debug build has its own identity, containers, and CloudKit container.

| Identifier | Value |
|---|---|
| App bundle identifier `<APP_ID>` | `<BUNDLE_ID>` (Release), `<BUNDLE_ID>.debug` (Debug), both platforms |
| App Group, iOS | `group.<APP_ID>` |
| App Group, macOS | `<TEAM>.<APP_ID>` (granted to team-signed tools without a profile) |
| CloudKit and ubiquity container | `iCloud.<APP_ID>` |
| Darwin change notification | `<APP_ID>.changed`, the only cross-process change signal |
| Agent socket | `<Mac group container>/Library/Application Support/TimeTracking/tracker.sock` |
| URL scheme | `timetracking` (Release), `timetracking-debug` (Debug) |
| WidgetKit push topic | `<APP_ID>.push-type.widgets` |
| APNs key Keychain service | `<BUNDLE_ID>.apns` (Release and Debug share it) |

On the Mac the app, agent, and tool share the group container. The store is `<group container>/Library/Application Support/TimeTracking/store.sqlite` (WAL); only the app runs the sync engine. The agent's local files live in the same folder. The block log and `settings.toml` are in `iCloud.<APP_ID>` (`spec_data_and_sync.md` §6). On iOS the app and its four extensions share `group.<APP_ID>`.

## 2. Configuration and build

### 2.1 Personal settings

Nothing personal is tracked. The git-ignored `local.mk` (tracked template `local.mk.example`) holds:

| Setting | Meaning | Default |
|---|---|---|
| `TEAM` | Development team id; required to build any app | empty |
| `BUNDLE_ID` | Release bundle identifier of both apps | `com.example.timetracking` |
| `APP_NAME` | Display and file name of the app bundles | `TimeTracking` |
| `DEVICE_<name>` | UDID of a physical device for `make device D=<name>` | none |
| `PREFIX` | Where `make install` links tools and completions | `$(HOME)/.local` |
| `ALIAS` | Optional second name for `timetracking` | empty |

Every building target first writes `Config/Local.xcconfig` (git-ignored) with `TT_BUNDLE_ID`, `TT_APP_NAME`, and `DEVELOPMENT_TEAM`, only when its content changes.

### 2.2 `Config/Project.xcconfig`

The only place for identifiers and signing; no target sets `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`, `CODE_SIGN_*`, `PROVISIONING_PROFILE*`, or `PRODUCT_NAME` in the project file.

- `TT_BUNDLE_SUFFIX_Debug = .debug`, `TT_BUNDLE_SUFFIX_Release =`, `TT_APP_ID = $(TT_BUNDLE_ID)$(TT_BUNDLE_SUFFIX_$(CONFIGURATION))`; bundle identifiers as in 1.1.
- `TT_CLOUDKIT_CONTAINER = iCloud.$(TT_APP_ID)`, `TT_APP_GROUP[sdk=iphone*] = group.$(TT_APP_ID)`, `TT_APP_GROUP[sdk=macosx*] = $(DEVELOPMENT_TEAM).$(TT_APP_ID)`, `TT_URL_SCHEME_Release = timetracking`, `TT_URL_SCHEME_Debug = timetracking-debug`; written into the Info.plists as `TTCloudKitContainer`, `TTAppGroup`, `TTURLScheme`, `TTTeamID`, `TTBundleID`.
- `PRODUCT_NAME = $(TT_APP_NAME)` for the two apps; module and executable names stay `TimeTracking`, `TimeTrackingiOS`, and `TimeTrackingAgent`. The display name (`CFBundleDisplayName`) is `$(TT_APP_NAME)` for user-visible bundles, with " Debug" appended in Debug.
- In Debug the two Mac bundles also carry " Debug" in their file names: `PRODUCT_NAME` is `$(TT_APP_NAME) Debug` for the Mac app and `TimeTrackingAgent Debug` for the agent (`TT_MAC_APP_NAME`, `TT_AGENT_NAME`), whose `CFBundleName` and `CFBundleDisplayName` follow. System Settings lists apps by bundle file name in Privacy & Security and names the app of `AssociatedBundleIdentifiers` in Login Items, and Finder shows file names, so without the suffix a permission granted to a development build looks like one granted to the installed app. Release names are unchanged; the iOS bundle file name is never shown and stays `<APP_NAME>.app`. The copy phase that embeds the agent refers to `$(BUILT_PRODUCTS_DIR)/$(TT_AGENT_NAME).app` by a plain file reference, because Xcode resolves a product reference under one configuration's name for every configuration.
- `MACOSX_DEPLOYMENT_TARGET = 27.0`, `IPHONEOS_DEPLOYMENT_TARGET = 27.0`, `TARGETED_DEVICE_FAMILY = 1,2`, no Mac Catalyst, no "Designed for iPad", `ARCHS[sdk=macosx*] = arm64`.
- `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for executables, `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
- `CODE_SIGN_STYLE = Automatic`, hardened runtime on the Mac, `ENABLE_APP_SANDBOX = NO` for Mac targets, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Release][sdk=macosx*] = NO` (no `get-task-allow` in Release; Mac entitlements files list everything explicitly), `CODE_SIGN_ENTITLEMENTS = Config/$(TARGET_NAME).entitlements`.
- `#include? "Local.xcconfig"` at the end.

### 2.3 Signing and entitlements

All builds are development-signed with automatic provisioning (`-allowProvisioningUpdates -allowProvisioningDeviceRegistration`). Without `TEAM`, every app-building target stops with "set TEAM in local.mk" before calling `xcodebuild`. Because all builds are development-signed, push tokens are APNs sandbox tokens and CloudKit uses each container's development environment in Release and Debug alike; there is no production promotion step.

| Target | Entitlements | Sandbox |
|---|---|---|
| `TimeTracking` | Apple Events; App Group; iCloud (CloudKit, iCloud Documents, `TT_CLOUDKIT_CONTAINER`); `aps-environment`; calendars | no |
| `TimeTrackingAgent` | Apple Events; App Group; iCloud as the app; `aps-environment` | no |
| `TimeTrackingCLI` | App Group | no |
| `TrackerEvent` | none | no |
| `TimeTrackingiOS` | App Group; iCloud (CloudKit, iCloud Documents); `aps-environment`; Family Controls (development) | yes |
| `TimeTrackingWidgets` | App Group; iCloud (CloudKit); `aps-environment` | yes |
| `TimeTrackingIntents` | App Group | yes |
| `TimeTrackingMonitor` | App Group; Family Controls | yes |
| `TimeTrackingWebExtension` | App Group | yes |

Mac targets use the hardened runtime. Sending pushes needs only the auth key (2.4), no entitlement. Info.plists: the Mac app carries `NSCalendarsFullAccessUsageDescription`, `NSAppleEventsUsageDescription`, the URL scheme, and `NSSupportsAutomaticTermination` false; the agent `NSAppleEventsUsageDescription`; the iOS app `NSCalendarsFullAccessUsageDescription`, `UIBackgroundModes` (`fetch`, `remote-notification`), `BGTaskSchedulerPermittedIdentifiers`, and the URL scheme.

After building, `build-mac` verifies the Release products (app, agent, both tools present; no `get-task-allow` or `com.apple.security.cs.` entitlement; hardened runtime; entitlements exactly as in the table; launchd plist names the agent) and fails on any violation.

### 2.4 APNs credentials and transport

The Mac app sends WidgetKit pushes itself, without a server; `spec_data_and_sync.md` §4.3 defines when and to whom. It uses the team's APNs auth key: a `.p8` file (PEM P-256 private key) from the developer account, its 10-character key id, and the team id.

The command `make apns-key P8=<path>/AuthKey_<KEYID>.p8 [KEY_ID=<id>]` validates that the file is a P-256 PEM private key and stores one generic-password item in the Mac's login Keychain: service `<BUNDLE_ID>.apns`, account the key id, secret the JSON `{"keyID": "…", "teamID": "<TEAM>", "p8": "<file contents>"}`, replacing an existing item of that service. The key id comes from the file name unless `KEY_ID` is given. The access list names `/Applications/<APP_NAME>.app` (run it after `make install`). The Makefile never prints the key, and `.gitignore` lists `*.p8`.

The `Push/` client reads the item, signs an ES256 JWT with CryptoKit (header `{"alg": "ES256", "kid": "<KEYID>"}`, claims `{"iss": "<TEAM>", "iat": <now>}`), reuses it for 50 minutes, and sends over HTTP/2 (`URLSession`):

- `POST https://api.sandbox.push.apple.com/3/device/<token>`
- headers `authorization: bearer <JWT>`, `apns-push-type: widgets`, `apns-topic: <APP_ID>.push-type.widgets`
- body `{"aps":{"content-changed":true}}`

It returns the response status and reason to the caller. Without the Keychain item it reports that no key is installed.

### 2.5 Makefile targets

The `help` target prints the targets grouped as below, from `##@` and `##` lines. The variable `DEVELOPER_DIR` defaults to `/Applications/Xcode.app/Contents/Developer`. Every `xcodebuild` call uses `-quiet -project TimeTracking.xcodeproj -derivedDataPath build.noindex -skipPackagePluginValidation -skipMacroValidation`.

| Group | Target | What it does |
|---|---|---|
| Build | `all`, `build` | `build-mac` and `build-ios` |
| | `build-mac` | Release Mac app with agent and tools; the checks of 2.3; unregisters every non-installed copy from LaunchServices |
| | `build-ios` | Release iOS app for `generic/platform=iOS` |
| | `build-sim` | Debug iOS app for the simulator |
| Develop | `sim` | `build-sim`, boots "TimeTracking iPhone" and "TimeTracking iPad" (`sim-create` if missing), installs, launches with `ARGS`, shows both in Device Hub |
| | `sim-create` | Creates the two simulators (2.6) unless they exist |
| | `stop` | Quits the app on both simulators |
| | `mac-debug` | Builds the Debug Mac app in `build.noindex/`, quits any running Debug app (from any checkout; it fails if the app does not quit within 10 seconds), and opens the new build with `ARGS` (`scripts/relaunch_mac_app.sh`) |
| | `demo` | Builds the Debug Mac and simulator apps; replaces the Debug store, its block log, and each simulator's store with the store fixture `FIXTURE` (`small`, `large`, `running`; default `small`) moved by whole days so that its 2024-03-14 is today (times of day kept, today's entries cut or dropped at now, a running entry keeps its age); opens the Mac app and launches it on both simulators; refuses any store outside a Debug or simulator container |
| | `mac-debug-unregister` | Quits the Debug app and agent, runs the Debug agent's `--unregister`, resets its TCC grants (`tccutil reset Accessibility\|AppleEvents\|SystemPolicyAllFiles <BUNDLE_ID>.debug.agent`), unregisters it from LaunchServices |
| | `logs`, `sim-logs` | Stream the unified log of the installed Mac app and agent, or of the simulator app |
| | `screenshots` | Simulator screenshots to `build.noindex/screenshots/` |
| Use | `install` | `build-mac`; quits app and agent; removes apps in `/Applications` with `BUNDLE_ID`; copies with `ditto`; registers with LaunchServices; links `timetracking` and `tracker-event` into `$(PREFIX)/bin` (plus `$(ALIAS)`); writes zsh, bash, and fish completions from the installed tool for each installed shell, also under the alias |
| | `mac` | `install`, then opens the app with `ARGS` |
| | `uninstall` | Quits app and agent, runs `--unregister`, removes the app, symlinks, and completions; containers, Keychain item, and iCloud data stay |
| | `apns-key` | 2.4 |
| | `device` | Release build for `DEVICE_<D>`, installs and launches with `devicectl` |
| | `iphone`, `ipad` | `make device D=iphone`, `D=ipad` |
| | `devices`, `console` | List known physical devices; relaunch on a device and stream its console |
| Test | `unit-test` (3 min) | `swift test` in the package, then `TimeTrackingTests`, `TimeTrackingAgentTests`, `TimeTrackingCLITests` |
| | `agent-test` (1 min) | `TimeTrackingAgentTests` |
| | `ui-test` (8 min) | Mac UI tests, iOS UI tests on both simulators |
| | `test` (15 min) | `unit-test`, `TimeTrackingiOSTests` on the iPhone simulator, `ui-test`; in-memory store and transport only |
| | `test-sync` (3 min) | `CloudKitTransport` tests against `iCloud.<BUNDLE_ID>.debug`; never part of `test` |
| Check | `lint` | SwiftFormat `--lint` and SwiftLint `lint --strict` from the package checkouts; no build |
| | `check-behaviors` | 3.2 |
| | `check-private` | `.githooks/check-private tree`: refuses tracked files with personal data (`local.mk` values, `.private-strings` lines, home directory, host name, git email, credentials, UDIDs, key and profile files) |
| | `check` | `lint`, `check-behaviors`, `check-private` |
| | `hooks` | `git config core.hooksPath .githooks`; run by every target that writes `Local.xcconfig` |
| Project | `secrets` | Writes `Config/Local.xcconfig` |
| | `xcode` | Writes the xcconfig and opens the project |
| | `skills` | Exports Xcode's agent skills into `.claude/skills/` (git-ignored) |
| | `clean` | Removes intermediates; keeps `build.noindex/Build/Products` |
| | `distclean` | Removes `build.noindex/`; refuses while the Debug agent is registered ("run make mac-debug-unregister first") |
| | `help` | The grouped listing |

The variable `ARGS` passes launch arguments. The apps understand `-UITesting YES` (in-memory store and transport, fixture, no animations), `-Fixture <name>`, and `-ResetState YES`; UI tests that must register the real Debug agent add `-RealAgent YES`, without which `-UITesting` uses a fake agent service. The tool reads `TIMETRACKING_STORE` and `TIMETRACKING_NOW` (`spec_automation.md`).

Every worktree of the repository shares the Debug bundle ID, the Debug store and agent, the simulators, and `/Applications`, so `sim`, `mac-debug`, `demo`, `install`, `unit-test`, `agent-test`, `ui-test`, `test`, and `test-sync` hold one runtime lock: `lockf` on `timetracking-runtime.lock` in the shared git directory (`git rev-parse --git-common-dir`), taken without waiting. While another process holds it, these targets fail with "another checkout is running ..." (make reports `Error 75`) before running anything; make calls nested inside a target that holds the lock run directly. The kernel releases the lock when make exits, also on an interrupt.

Git hooks `pre-commit`, `commit-msg`, and `pre-push` run `check-private` in modes `staged`, `message <file>`, and `push`; `pre-push` also runs `make lint`. Bypassing them is not allowed.

### 2.6 Simulators

The simulators are "TimeTracking iPhone" (`iPhone-17-Pro`) and "TimeTracking iPad" (`iPad-Pro-13-inch-M5-12GB`). `sim-create` creates a missing one on the newest runtime that supports its device type (simctl's choice when no runtime is named); an existing one stays on its runtime. The Makefile and scripts name them, and `scripts/simulator.sh udid <name>` turns the name into the UDID of the available device of that name (on the newest runtime that has one) at run time; every `xcodebuild` destination is `platform=iOS Simulator,id=<UDID>` and every `simctl` call takes the UDID, because a `name=` destination implies `OS=latest` and misses a device on an older runtime. No UDID is written into a tracked file. `scripts/simulator.sh show` brings the simulators to the front in Xcode's Device Hub (`devices://device/open?id=<UDID>`), which replaced Simulator.app. Simulator builds are team-signed; tests switch CloudKit off through the in-memory transport, never through entitlements.

## 3. Testing

### 3.1 Kinds of tests

| Kind | Framework | Target | Covers |
|---|---|---|---|
| Library | Swift Testing | `TimeTrackingCoreTests` | Model, store, midnight split, outbox, queries, reports, import and export, CSV, activity reader, suggestions, the APNs request (test key generated in the test), multi-store sync against `InMemoryTransport` |
| Sync integration | Swift Testing, `.tags(.sync)` | same | `CloudKitTransport` and the `LiveState` fetch in a test-created zone; `make test-sync` only |
| View models | Swift Testing | `TimeTrackingTests`, `TimeTrackingiOSTests` | Timer modes, Pomodoro, idle prompt, picker, section state, status item title |
| Agent | Swift Testing | `TimeTrackingAgentTests` | Resolvers against fixtures, presence, Blocker, exclusions, log writing, settings reload, socket |
| Tool | Swift Testing | `TimeTrackingCLITests` | The tool as a subprocess: stdout, stderr, exit codes |
| UI | XCTest (XCUITest) | `TimeTrackingUITests`, `TimeTrackingiOSUITests` | What only real windows show |
| Makefile | shell | `scripts/test_make.sh` | `Local.xcconfig` writing, `help`, `check-behaviors`, `apns-key` against a temporary keychain |

UI tests find controls by accessibility identifier (`timer.startButton`), never by visible text. The `-UITesting` argument may switch storage and transport, load a fixture, and disable animations; it may not change what a control does.

### 3.2 Behavior identifiers

Each spec has one "Testable behaviors" list numbered continuously from 1, with the prefix `ARCH`, `DATA` (data and sync), `TW` (the Timer and the main window, spec_timer_window.md), `MB` (menu bar), `PP`, `PC`, `PR`, `PA` (the Projects, Calendar, Reports, and Activity sections), `TRK` (tracker), `IOS`, or `AUTO`. Each item names an observable input and result with concrete values.

A test carries the identifier in its display name, `@Test("TW-1 releasing below 200 pt collapses to the bar")`, or for XCUITest in the method name, `testTW1_collapseBelowThreshold()`. One test may cover several numbers. The script `scripts/check_behaviors.sh` reads every `spec/spec_*.md`, checks that the numbers are continuous, and fails on a number without a test or a test identifier no spec defines.

### 3.3 What runs where

The `test` target needs no network and no permission grant; the Mac UI tests run the Debug app with `-UITesting YES`, which leaves the agent unregistered. View model tests for iOS run on the iPhone simulator only; UI tests on both. A test over 10 seconds is tagged `.slow` and runs only in `make test`. Tests never sleep: they use `ManualClock`, drive the agent's tick, and fix `TIMETRACKING_NOW`.

### 3.4 Fixtures

The folder `Fixtures/` at the root serves every test target and the SwiftUI previews:

- `Store/<name>.json` in the JSON export format: `empty`, `small` (3 clients, 5 areas, 12 projects, two weeks of entries), `large` (two years), `running` (an entry running for 25 minutes).
- `Activity/blocks/YYYY-MM.jsonl` and `current.json`.
- `Agent/<adapter>/*.txt`, recorded and anonymized by `TimeTrackingAgent --record`.
- `Agent/samples/<day>.jsonl` with `<day>.expected.jsonl`.

Fixture dates are in 2024; the test clock is `2024-03-14T10:00:00` local time. Fixtures are synthetic or anonymized, and `check-private` covers them.

## 4. Code conventions

### 4.1 Swift

Swift 6 with complete strict concurrency and warnings as errors. Executables default to `MainActor` isolation (the agent too); the package defaults to nonisolated. No `#available` or `@available` for older systems, no Combine, no `DispatchQueue` outside AppKit glue, no `print` outside the tools' output. Logging uses `os.Logger`, one subsystem per process (its bundle identifier), one category per module. Errors are typed `enum`s per module conforming to `LocalizedError`; user-visible text comes from the view layer. One primary type per file, extensions in `Type+Topic.swift`, a header comment naming the defining spec section. The package declares access control explicitly.

### 4.2 SwiftUI and AppKit

SwiftUI with `@Observable`, `@State`, `@Environment`, `@Bindable`; no `ObservableObject`. AppKit only where SwiftUI has no equivalent, each use in one file under `TimeTracking/Platform/` behind a SwiftUI-facing type:

| Need | Used |
|---|---|
| Status item | `NSStatusItem` with `NSMenu`; header view in `NSHostingView` |
| Global shortcuts | KeyboardShortcuts package |
| Pinned Mini Timer | `.windowLevel(.floating)`; `NSWindow.level` only if the modifier cannot change at run time |
| Hidden title bar buttons in compact mode | `NSWindow.standardWindowButton(_:)` |
| Dock menu | `applicationDockMenu(_:)` |

UIKit is not expected in the iOS target.

### 4.3 Formatting and lint

SwiftFormat and SwiftLint run as build phases of the two apps in Debug, from package checkouts. SwiftFormat rewrites sources (`.swiftformat`: indent 4, upper-case acronyms, trailing commas, `self` only in initializers); SwiftLint fixes what it can and reports the rest (`.swiftlint.yml` opts into all rules, lists disabled ones with a reason, and has a custom rule against `#available` and `@available`). Zero warnings, zero SwiftLint findings.

## 5. Dependencies

System frameworks first. Third-party packages, pinned exactly in the committed `Package.resolved`:

| Package | Use |
|---|---|
| `groue/GRDB.swift` 7.x | SQLite (WAL, `DatabasePool`, migrations, records) for the store and the agent's samples |
| `apple/swift-argument-parser` 1.x | The tool's commands, help, and completions |
| `sindresorhus/KeyboardShortcuts` | Recordable global shortcuts `showHideTimer` and `continueStop`, in `Platform/GlobalShortcuts.swift` |
| `LebJe/TOMLKit` | `settings.toml` and the automation description file |
| `nicklockwood/SwiftFormat`, `SimplyDanny/SwiftLintPlugins` | Build-time tools, not linked |

No networking, HTTP/2, JWT, Markdown, logging, or dependency-injection packages.

## 6. Repository layout

```
TimeTracking/
├── Makefile  local.mk.example  local.mk  README.md  CLAUDE.md
├── .gitignore  .swiftformat  .swiftlint.yml
├── .githooks/            pre-commit  commit-msg  pre-push  check-private
├── Config/               Project.xcconfig  Local.xcconfig  <target>.entitlements  *-Info.plist
├── TimeTracking.xcodeproj/
├── Packages/TimeTrackingCore/   Package.swift  Sources/TimeTrackingCore/<folders of 1.2>  Tests/
├── TimeTracking/         App/ Timer/ MainWindow/ MenuBar/ Settings/ Live/ Platform/ Resources/ …
├── TimeTrackingiOS/      App/ Timer/ iPad/ Background/ Resources/ …
├── Shared/
├── TimeTrackingAgent/  TrackerEvent/  TimeTrackingCLI/
├── TimeTrackingWidgets/  TimeTrackingIntents/  TimeTrackingMonitor/  TimeTrackingWebExtension/
├── <test bundles of 1.1>/
├── Fixtures/             Store/ Activity/ Agent/
├── scripts/              check_behaviors.sh  unregister_builds.sh  debug_unregister.sh  common.sh  test_make.sh  make_fixtures.swift
├── spec/
└── build.noindex/
```

The `.gitignore` lists `build.noindex/`, `DerivedData/`, `xcuserdata/`, `*.xcuserstate`, `local.mk`, `Config/Local.xcconfig`, `CLAUDE.local.md`, `.private-strings`, `.claude/settings.local.json`, `.claude/skills/`, `.DS_Store`, `*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, and `*.provisionprofile`.

## 7. Implementation order

### 7.1 The first commit

A skeleton that builds, installs, and passes `make test` before any feature exists: the Makefile, `local.mk.example`, dotfiles, hooks, and scripts; `Project.xcconfig` and every entitlements and Info.plist file; the project with every target of 1.1 compiling an empty `main` or `App`, the embedding copy phases, the launchd plist phase, and the schemes `TimeTracking`, `TimeTrackingiOS`, and `TimeTrackingAgent`; the package with the folders of 1.2 and `Support/`; `CLAUDE.md` condensing sections 1.3, 1.5, 2.1, 2.2, 3, 4, and 5; `Fixtures/Store/empty.json`. Every ARCH behavior except ARCH-8, ARCH-11, ARCH-16, ARCH-17, and ARCH-19 passes at this commit; those pass once the store (17, 19), the agent and its Tracker pane (8, 16), and the push client (11) exist.

### 7.2 Order across components

| Step | Component | Depends on |
|---|---|---|
| 1 | Architecture skeleton | |
| 2 | Data, local part (`Model/`, `Store/`, `Queries/`, `Interchange/`, `InMemoryTransport`, fixtures) | 1 |
| 3 | Timer, main window, and menu bar | 2 |
| 4 | Tracker agent phases 1 to 5, `tracker-event` (parallel to 3) | 1, `Activity/` |
| 5 | Sync (`CloudKitTransport`, coordinator, `LiveState`) | 2, 3 |
| 6 | Automation (tool with `import`, App Intents) | 2 |
| 7 | Sections: Projects, Reports, Calendar, Activity | 2, 3; Calendar and Activity also 4 |
| 8 | iOS: Timer, widgets, controls, intents, widget pushes (`Push/`, `make apns-key`); then iPad tabs; then activity collection (tracker phases 7 to 9) | 5, 6; iPad 7; collection 4 |

Each step ends with its behaviors green and with `make install` producing a usable app.

## 8. Testable behaviors

1. With no `local.mk`, `swift test` in the package passes without signing, network, or permission prompts.
2. Running `make secrets` writes `Config/Local.xcconfig` with `TT_BUNDLE_ID`, `TT_APP_NAME`, and `DEVELOPMENT_TEAM`; a second run without changes leaves its modification time unchanged.
3. With `TEAM` unset, `make build-mac`, `build-ios`, `sim`, `install`, and `device D=x` each exit non-zero with "set TEAM in local.mk" before invoking `xcodebuild`.
4. A Release Mac build contains `Contents/Library/LoginItems/TimeTrackingAgent.app`, `Contents/Library/LaunchAgents/<BUNDLE_ID>.agent.plist` whose `BundleProgram` points at the agent's executable, `Contents/Helpers/timetracking`, `Contents/Helpers/tracker-event`, and no `Contents/Frameworks/`.
5. Every Release Mac and iOS bundle's entitlements equal the table of 2.3, no Release Mac product carries `get-task-allow` or a `com.apple.security.cs.` entitlement, each Mac product has the hardened runtime, and `make build-mac` fails when any Mac check is violated.
6. The Debug identifiers are `<BUNDLE_ID>.debug`, `<BUNDLE_ID>.debug.agent`, `group.<BUNDLE_ID>.debug`, `<TEAM>.<BUNDLE_ID>.debug`, `iCloud.<BUNDLE_ID>.debug`, and scheme `timetracking-debug`; no Release identifier contains `.debug`.
7. Changing `APP_NAME` renames the app bundles and display names and leaves module names, executable names, and bundle identifiers unchanged.
8. Launching the freshly installed Mac app does not register the agent (`SMAppService` status `notRegistered`); clicking "Enable Tracker" in the Tracker pane registers it.
9. Running `make apns-key P8=<dir>/AuthKey_ABC123DEFG.p8` with a valid key creates one generic-password item with service `<BUNDLE_ID>.apns`, account `ABC123DEFG`, and a secret whose `keyID` is `ABC123DEFG`, `teamID` equals `TEAM`, and `p8` equals the file content; a second run leaves exactly one item.
10. Running `make apns-key` with a missing file or a key that is not P-256 exits non-zero and leaves the keychain unchanged.
11. For key id `ABC123DEFG`, team `T`, app id `X`, and token `abcd`, the push client sends `POST https://api.sandbox.push.apple.com/3/device/abcd` with `apns-push-type: widgets`, `apns-topic: X.push-type.widgets`, body `{"aps":{"content-changed":true}}`, and a JWT with `alg` `ES256`, `kid` `ABC123DEFG`, `iss` `T`, and a signature that verifies with the public key; a request 49 minutes later reuses the JWT and one 51 minutes later carries a new one.
12. Running `make check-behaviors` exits non-zero and lists `TW-999` when the Timer spec defines item 999 without a test; it also reports a test identifier that no spec defines and a non-continuous list.
13. Running `make help` lists every target of 2.5 under its group heading.
14. Running `make clean` keeps `build.noindex/Build/Products`; `make distclean` removes `build.noindex/`, keeps `local.mk`, and refuses while `launchctl print gui/<uid>/<BUNDLE_ID>.debug.agent` succeeds.
15. Running `make lint` exits non-zero on a SwiftLint violation, a formatting difference, or an `#available` check, without building; a build with a compiler warning fails.
16. The agent run with `--replay Fixtures/Agent/samples/<day>.jsonl` writes the blocks of `<day>.expected.jsonl` (byte for byte after normalizing the header's `dev` field) and exits 0.
17. Launching either app with `-UITesting YES -Fixture small` shows the fixture's data, writes nothing to the on-disk store, and performs no CloudKit operation.
18. Running `make sim-create` creates both simulators if absent and does nothing if they exist; `make test` passes with them freshly created.
19. The Debug Mac app, Debug agent, and Debug tool open the same `store.sqlite` under `~/Library/Group Containers/<TEAM>.<BUNDLE_ID>.debug/` and never a file in the Release container.
20. Running `make install` then `$(PREFIX)/bin/timetracking --version` prints the installed app's version; `make uninstall` removes only the symlinks and completion files it wrote under `$(PREFIX)` and keeps the `<BUNDLE_ID>.apns` Keychain item.
21. A `tracker-event` invocation with the agent not running exits non-zero within 100 ms.
22. A `git commit` whose staged change contains the value of `TEAM` is refused by the pre-commit hook.
23. Seeding fixture `running` at 15:00 local time on 2026-10-30 (`make demo FIXTURE=running`) puts the entries of 2024-03-13 on 2026-10-29 at the same local times, starts the running entry at 14:35, and leaves no entry after 15:00; `make demo` names only the Debug container, and a store outside a Debug or simulator container is refused and left unchanged.
24. In Debug the Mac app is `<APP_NAME> Debug.app` and the agent `Contents/Library/LoginItems/TimeTrackingAgent Debug.app`, both with "Debug" in `CFBundleName` and `CFBundleDisplayName`, the launchd plist's `BundleProgram` names the renamed agent, and every iOS bundle's display name ends in " Debug"; executable names are unchanged, and no Release bundle's file name, `CFBundleName`, or `CFBundleDisplayName` contains "Debug".
25. While another process holds `<git common dir>/timetracking-runtime.lock`, `make agent-test` exits non-zero with "another checkout is running" without invoking `xcodebuild`; once it is released, `make agent-test` invokes `xcodebuild`; and a `make agent-test` run from inside a target that holds the lock invokes `xcodebuild` instead of failing.
26. With "TimeTracking iPhone" available on iOS 27.0 and iOS 27.2, `scripts/simulator.sh udid "TimeTracking iPhone"` prints the UDID of the iOS 27.2 device; "TimeTracking iPad" does not match "TimeTracking iPad Pro"; an unknown name exits non-zero naming `make sim-create`. `make build-sim`, `ui-test`, and `test` pass simulator destinations as `platform=iOS Simulator,id=<UDID>` looked up by name, never `name=`.

## 9. Decisions

- Two app targets, Mac and iOS: their window structures differ too much for one multiplatform target.
- The library is a statically linked local package, so the tools are self-contained.
- The Mac app is unsandboxed so app, agent, and tool share one container; the hardened runtime stays on.
- Debug is a separate identity with its own containers, so development never touches the user's data.
- All builds use CloudKit's development environment and APNs sandbox; no promotion step exists.
- The Mac app sends widget pushes with the team's key from the Keychain, so no server is needed.
- The agent uses `SMAppService.agent` for `KeepAlive` and a Mach service.
- Swift Testing everywhere except the UI test bundles, which XCUITest ties to XCTest.

## 10. Interfaces

Provided:

- Target names and bundle identifiers (1.1), including `TimeTrackingIntents`.
- Identifiers and containers (1.5), including `<APP_ID>.changed` and the widget push topic.
- The library folders (1.2), GRDB, TOMLKit.
- APNs credentials and the push client (2.4).
- The Makefile targets `install`, `uninstall`, and `test`.

Assumed:

- Data spec: store schema and path, `LiveState`, `LiveStatePublisher`, `WidgetPushSender` and its sending rules, `Device.widgetPushToken`, the JSON export format used by fixtures.
- Tracker spec: agent flags, local files in the group container, the Tracker pane with "Enable Tracker".
- Automation spec: `TIMETRACKING_STORE`, `TIMETRACKING_NOW`.
- Timer and menu bar specs: KeyboardShortcuts names `showHideTimer` and `continueStop`.
- iOS spec: `TimeTrackingWidgetPushHandler`, wrapper intents for widget and control buttons.
