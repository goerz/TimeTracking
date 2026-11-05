# Spec: Project Architecture and Build System

The Xcode project and its targets, the shared library, identifiers and entitlements, the APNs credentials, the build system, testing, code conventions, and dependencies. The product name in code is `TimeTracking`; the name the user sees is a personal build setting (2.1).

Toolchain: macOS 27, Xcode 27, Swift 6, deployment targets macOS 27.0 and iOS 27.0, and a paid Apple Developer Program membership. The apps are installed from Xcode or the Makefile only; there is no App Store, TestFlight, or Developer ID distribution.

## 1. Targets and the shared library

### 1.1 Targets

One Xcode project, `TimeTracking.xcodeproj`, and one local Swift package, `Packages/TimeTrackingCore`; there is no workspace. Every executable links the package statically (no `Contents/Frameworks/`, no rpath), so the tools are self-contained. The Mac and iOS apps are separate targets because their window structures differ too much for one multiplatform target.

| Target | Kind and product | Spec |
|---|---|---|
| `TimeTrackingCore` | Swift package library (macOS, iOS) | `spec_data_and_sync.md` |
| `TimeTracking` | Mac app, `<APP_NAME>.app` | `spec_timer.md`, `spec_menubar.md`, `spec_calendar.md`, `spec_reports.md`, `spec_projects.md`, `spec_activity.md` |
| `TimeTrackingAgent` | Mac login item, `TimeTrackingAgent.app` at `Contents/Library/LoginItems/` | `spec_activity_tracking.md` |
| `TimeTrackingCLI` | Tool `timetracking` at `Contents/Helpers/` | `spec_automation.md` |
| `TrackerEvent` | Tool `tracker-event` at `Contents/Helpers/` | `spec_activity_tracking.md` |
| `TimeTrackingiOS` | iOS app (iPhone and iPad), `<APP_NAME>.app` | `spec_ios.md` |
| `TimeTrackingWidgets`, `TimeTrackingIntents`, `TimeTrackingMonitor`, `TimeTrackingWebExtension` | iOS extensions: widgets and controls; Focus filter and log-activity-event intent; DeviceActivity monitor; Safari web extension | `spec_ios.md` |

Test bundles: `TimeTrackingCoreTests` (package), `TimeTrackingTests`, `TimeTrackingUITests`, `TimeTrackingiOSTests`, `TimeTrackingiOSUITests`, `TimeTrackingAgentTests`, `TimeTrackingCLITests`. There is no Mac widget and no Apple Watch target.

### 1.2 The library

One Swift target with the folders `Model/`, `Store/`, `Sync/`, `Push/`, `Queries/`, `Interchange/`, `Activity/`, `TimeBlocks/`, `Intents/`, and `Support/`; the package also holds the development tools `MakeFixtures` and `DemoStore`, which no app links. The library never imports SwiftUI, AppKit, UIKit, or WidgetKit. Observed types are `@MainActor @Observable`, the store and sync coordinator are actors, and model values are `Sendable` structs.

### 1.3 What each target holds

User interface targets hold views, view state, and platform glue only. A view model may hold selection, drafts, sort order, and presentation state and call the library; it may not compute totals, overlaps, or export formats. If a view model test needs a store fixture, the logic belongs in the library.

| Folder | Holds |
|---|---|
| `TimeTracking/` | Mac scenes, Timer, sections, status item, settings, agent registration, global shortcuts, AppKit glue (4.2), URL handler; it runs `LiveStatePublisher` and `WidgetPushSender` |
| `TimeTrackingiOS/` | iOS scenes, Timer tab, iPad tabs, background refresh and silent pushes, widget push token upload, URL handler, the iPhone's Apple Health import |
| `Shared/` | Views compiled into both apps; platform differences are `#if os(macOS)` around a modifier |
| `WidgetShared/`, `CollectionShared/` | Code compiled into the iOS app and the widget extension, and into the iOS app and the monitor extension |
| `AppResources/` | The app icon and `AccentColor` asset, in the Mac app, the agent, and the iOS app (`spec_design.md` §9) |
| `TimeTrackingAgent/` | The tracker; links the library and GRDB; `LSUIElement`; flags `--record <folder>`, `--replay <file>`, `--unregister` |
| `TrackerEvent/` | Connects to the agent's socket, writes one line, exits; links only Foundation |
| `TimeTrackingCLI/` | Argument parsing and output formatting; everything else through the library; never touches CloudKit |
| iOS extensions | Rendering and forwarding only |
| `AppTestSupport/` | Test helpers compiled into both hosted test bundles |

### 1.4 The agent as a login item

The agent is embedded at `Contents/Library/LoginItems/TimeTrackingAgent.app` and registered with `SMAppService.agent(plistName: "<APP_ID>.agent.plist")`, which gives it `KeepAlive` and a Mach service. A build phase generates that plist into `Contents/Library/LaunchAgents/`: `Label` and the Mach service are the agent's bundle identifier, `BundleProgram` is the agent's executable, `AssociatedBundleIdentifiers` names the app, `KeepAlive` is true, `ProcessType` is `Background`.

The agent is always signed with the team's development certificate, because TCC keys Accessibility and Full Disk Access grants to the signing identity. As the agent's responsible process, the app holds its Full Disk Access grant, while Accessibility is checked for the agent itself (`spec_activity_tracking.md` §5, §7.4).

The Mac app registers the agent only when the user clicks "Enable Tracker" in the settings window's Tracker pane; the first-launch alert offers to open that pane (`spec_timer.md` §8.2). The Debug app registers the Debug agent, so a development build never replaces the recording agent.

### 1.5 Identifiers and containers

Every identifier derives from `TT_APP_ID`, so a Debug build has its own identity and containers and development never touches the user's data. Code reads them through `AppIdentity` from the `TT*` Info.plist keys and never hard-codes one.

| Identifier | Value |
|---|---|
| App bundle identifier `<APP_ID>` | `<BUNDLE_ID>` (Release), `<BUNDLE_ID>.debug` (Debug), both platforms |
| Agent and extensions | `<APP_ID>.agent`, `.widgets`, `.intents`, `.monitor`, `.web-extension`; the two tools have none |
| App Group, iOS | `group.<APP_ID>` |
| App Group, macOS | `<TEAM>.<APP_ID>` (granted to team-signed tools without a profile) |
| CloudKit and ubiquity container | `iCloud.<APP_ID>` |
| Darwin change notification | `<APP_ID>.changed`, the only cross-process change signal |
| Agent socket | `<Mac group container>/Library/Application Support/TimeTracking/tracker.sock` |
| URL scheme | `timetracking` (Release), `timetracking-debug` (Debug) |
| WidgetKit push topic | `<APP_ID>.push-type.widgets` |
| APNs key Keychain service | `<BUNDLE_ID>.apns` (Release and Debug share it) |

Mac targets are unsandboxed so that the app, agent, and tool share one group container. The store is `<group container>/Library/Application Support/TimeTracking/store.sqlite` (WAL), only the app runs the sync engine, and the agent's local files live in the same folder. The block log and `settings.toml` are in `iCloud.<APP_ID>` (`spec_data_and_sync.md` §6). On iOS the app and its four extensions share `group.<APP_ID>`.

## 2. Configuration and build

### 2.1 Personal settings

Nothing personal is tracked. The git-ignored `local.mk` (template `local.mk.example`) holds `TEAM` (required to build any app), `BUNDLE_ID` (default `com.example.timetracking`), `APP_NAME` (default `TimeTracking`), `DEVICE_<name>` (the UDID for `make device D=<name>`), `PREFIX` (default `$(HOME)/.local`), and `ALIAS` (an optional second name for `timetracking`). Every building target first writes `Config/Local.xcconfig` (git-ignored) from them, only when its content changes.

### 2.2 `Config/Project.xcconfig`

The only place for identifiers and signing: no target sets `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`, `CODE_SIGN_*`, `PROVISIONING_PROFILE*`, or `PRODUCT_NAME` in the project file. Per-target values come from tables keyed by `TARGET_NAME`. The apps' `PRODUCT_NAME` follows `TT_APP_NAME`; module and executable names stay `TimeTracking`, `TimeTrackingiOS`, and `TimeTrackingAgent`.

In Debug the two Mac bundles carry " Debug" in their file names (`TT_MAC_APP_NAME`, `TT_AGENT_NAME`), and every display name ends in " Debug". System Settings lists apps by bundle file name in Privacy & Security and Login Items, and Finder shows file names, so without the suffix a permission granted to a development build looks like one granted to the installed app. The iOS bundle file name is never shown and stays `<APP_NAME>.app`. The copy phase embeds the agent through a plain file reference, because Xcode resolves a product reference under one configuration's name for every configuration.

Shipping products default to `MainActor` isolation, test bundles to nonisolated. Mac entitlements files list everything explicitly, and Release Mac builds don't inject base entitlements, so they carry no `get-task-allow`.

### 2.3 Signing and entitlements

All builds are development-signed with automatic provisioning. Without `TEAM`, every app-building target stops with "set TEAM in local.mk" before calling `xcodebuild`. Push tokens are therefore APNs sandbox tokens and CloudKit uses each container's development environment, in Release and Debug alike; there is no production promotion step.

| Target | Entitlements | Sandbox |
|---|---|---|
| `TimeTracking` | Apple Events; App Group; iCloud (CloudKit, iCloud Documents, `TT_CLOUDKIT_CONTAINER`); `aps-environment`; calendars | no |
| `TimeTrackingAgent` | Apple Events; App Group; iCloud as the app; `aps-environment` | no |
| `TimeTrackingCLI` | App Group | no |
| `TrackerEvent` | none | no |
| `TimeTrackingiOS` | App Group; iCloud (CloudKit, iCloud Documents); `aps-environment`; Family Controls (development); HealthKit (read only) | yes |
| `TimeTrackingWidgets` | App Group; iCloud (CloudKit); `aps-environment` | yes |
| `TimeTrackingIntents` | App Group | yes |
| `TimeTrackingMonitor` | App Group; Family Controls | yes |
| `TimeTrackingWebExtension` | App Group | yes |

Mac targets use the hardened runtime. Sending pushes needs only the auth key (2.4), no entitlement.

After building, `build-mac` and `build-ios` verify the Release products with `scripts/check_products.sh` and fail on any violation: bundle layout, entitlements exactly as in `Config/`, signature and team, on the Mac the hardened runtime, no `get-task-allow` or `com.apple.security.cs.` entitlement, and the launchd plist.

### 2.4 APNs credentials and transport

The Mac app sends WidgetKit pushes itself with the team's APNs auth key from the Keychain, so no server is needed; `spec_data_and_sync.md` §4.3 defines when and to whom.

The command `make apns-key P8=<path>/AuthKey_<KEYID>.p8 [KEY_ID=<id>]` validates that the file is a P-256 PEM private key and stores one generic-password item in the login Keychain: service `<BUNDLE_ID>.apns`, account the key id (10 upper-case letters or digits, from the file name unless `KEY_ID` is given), secret the JSON `{"keyID": "…", "teamID": "<TEAM>", "p8": "<file contents>"}`. It replaces an existing item of that service. The access list names `/Applications/<APP_NAME>.app`, so it runs after `make install`. The key is never printed.

The client signs an ES256 JWT (header `{"alg": "ES256", "kid": "<KEYID>"}`, claims `{"iss": "<TEAM>", "iat": <now>}`), reuses it for 50 minutes, and sends over HTTP/2:

- `POST https://api.sandbox.push.apple.com/3/device/<token>`
- headers `authorization: bearer <JWT>`, `apns-push-type: widgets`, `apns-topic: <APP_ID>.push-type.widgets`
- body `{"aps":{"content-changed":true}}`

It returns the response status and reason to the caller. Without the Keychain item it reports that no key is installed.

### 2.5 Makefile targets

The target `help` describes each target under its group. The Makefile sets `DEVELOPER_DIR` to `/Applications/Xcode.app/Contents/Developer`, and `XCFLAGS` passes extra build settings to every `xcodebuild` call.

| Group | Targets |
|---|---|
| Build | `all`, `build`, `build-mac`, `build-ios`, `build-sim` |
| Develop | `sim`, `sim-create`, `stop`, `mac-debug`, `demo`, `mac-debug-unregister`, `logs`, `sim-logs`, `screenshots` |
| Use | `install`, `mac`, `uninstall`, `apns-key`, `device`, `iphone`, `ipad`, `devices`, `console` |
| Test | `unit-test`, `agent-test`, `ui-test`, `test`, `test-sync` |
| Check | `lint`, `check-behaviors`, `check-private`, `check`, `hooks` |
| Project | `secrets`, `xcode`, `skills`, `clean`, `distclean`, `help` |

A few rules go beyond the help text. After a Release Mac build, every copy of the app other than the installed one is unregistered from LaunchServices, because build products otherwise compete with it for URL schemes, login items, and "Open With". The target `install` replaces every app in `/Applications` with `BUNDLE_ID`; `uninstall` removes the app and only the symlinks and completions `install` wrote, keeping containers, the Keychain item, and iCloud data. The target `mac-debug` quits any running Debug app, from any checkout, so the new build is the one that runs, and fails if the app does not quit within 10 seconds. The target `mac-debug-unregister` also resets the Debug agent's TCC grants, and `distclean` refuses while the Debug agent is registered.

The target `demo` replaces the Debug store, its block log, and each simulator's store with the store fixture `FIXTURE` (default `small`) moved by whole days so that its 2024-03-14 is the current date: times of day are kept, that date's entries are cut or dropped at now, and a running entry keeps its age. It refuses any store outside a Debug or simulator container.

The variable `ARGS` passes launch arguments. The apps understand `-UITesting YES` (in-memory store and transport, fixture, no animations; a fake agent service unless `-RealAgent YES` is added), `-Fixture <name>`, `-ResetState YES`, and under `-UITesting` also `-LoginItemLaunch YES`, which launches the Mac app as if opened as a login item (`spec_timer.md` §1.3). The tool reads `TIMETRACKING_STORE` and `TIMETRACKING_NOW` (`spec_automation.md`).

Every worktree of the repository shares the Debug bundle ID, the Debug store and agent, the simulators, and `/Applications`, so `sim`, `mac-debug`, `demo`, `install`, `unit-test`, `agent-test`, `ui-test`, `test`, and `test-sync` hold one runtime lock: `lockf` on `timetracking-runtime.lock` in the shared git directory, taken without waiting. While another process holds it, these targets fail with "another checkout is running ..." (`Error 75`) before running anything; make calls nested inside a target that holds the lock run directly. The kernel releases the lock when make exits.

Git hooks `pre-commit`, `commit-msg`, and `pre-push` run `check-private` in modes `staged`, `message <file>`, and `push`; `pre-push` also runs `make lint`. They are never bypassed.

### 2.6 Simulators

The simulators are "TimeTracking iPhone" (`iPhone-17-Pro`) and "TimeTracking iPad" (`iPad-Pro-13-inch-M5-12GB`). The target `sim-create` creates a missing one on the newest runtime that supports its device type; an existing one stays on its runtime. The script `scripts/simulator.sh udid <name>` turns the name into the UDID of the available device of that name, on the newest runtime that has one, at run time. Every `xcodebuild` destination is `platform=iOS Simulator,id=<UDID>` and every `simctl` call takes the UDID, because a `name=` destination implies `OS=latest` and misses a device on an older runtime. No UDID is written into a tracked file. Simulator builds are team-signed; tests switch CloudKit off through the in-memory transport, never through entitlements.

## 3. Testing

### 3.1 Kinds of tests

Tests use Swift Testing, except the UI test bundles, which XCUITest ties to XCTest.

| Kind | Target | Run by |
|---|---|---|
| Library | `TimeTrackingCoreTests`, with multi-store sync against `InMemoryTransport` | `swift test`, `make unit-test` |
| Sync integration (`.tags(.sync)`) | `CloudKitTransport` and the `LiveState` fetch in a test-created zone | `make test-sync` only |
| View models | `TimeTrackingTests`, `TimeTrackingiOSTests` | `make unit-test`, `make test` |
| Agent | `TimeTrackingAgentTests` | `make agent-test` |
| Tool | `TimeTrackingCLITests`, the tool as a subprocess | `make unit-test` |
| UI | `TimeTrackingUITests`, `TimeTrackingiOSUITests`, for what only real windows show | `make ui-test` |
| Makefile, scripts, hooks | Shell tests; `--build`, `--products`, `--sim`, and `--install` add slower checks | `scripts/test_make.sh` |

UI tests find controls by accessibility identifier (`timer.startButton`), never by visible text. The `-UITesting` argument may switch storage and transport, load a fixture, and disable animations; it may not change what a control does.

### 3.2 Behavior identifiers

Each spec except the design language has one "Testable behaviors" list numbered continuously from 1, with the prefix `ARCH`, `DATA` (data and sync), `TM` (the Timer and the main window), `MB` (menu bar), `PP`, `PC`, `PR`, `PA` (the Projects, Calendar, Reports, and Activity sections), `TRK` (tracker), `IOS`, or `AUTO`. Each item names an observable input and result with concrete values.

A test carries the identifier in its display name, `@Test("TM-1 releasing below 200 pt collapses to the bar")`, in an XCUITest method name, `testTM1_collapseBelowThreshold()`, or in `scripts/test_make.sh`, `behavior "ARCH-2 ..."`. One test may cover several numbers. The script `scripts/check_behaviors.sh` (`make check-behaviors`) fails on a number without a test, a test identifier no spec defines, or a non-continuous list.

### 3.3 What runs where

The `test` target needs no network and no permission grant; the Mac UI tests run the Debug app with `-UITesting YES`, which leaves the agent unregistered. View model tests for iOS run on the iPhone simulator only, UI tests on both. A test over 10 seconds is tagged `.slow`; the library's performance suites run only in `make test`, in an optimized build, one test at a time. Tests never sleep: they use `ManualClock`, drive the agent's tick, and fix `TIMETRACKING_NOW`.

### 3.4 Fixtures

The folder `Fixtures/` serves every test target and the SwiftUI previews: `Store/<name>.json` in the JSON export format (`empty`, `small` with 3 clients, 5 areas, 12 projects, and two weeks of entries, `large` with two years, `running` with an entry running for 25 minutes), `Activity/blocks/`, `Agent/<adapter>/*.txt` from `TimeTrackingAgent --record`, and `Agent/samples/`. Fixture dates are in 2024; the test clock is `2024-03-14T10:00:00` local time. Fixtures are synthetic or anonymized, and `check-private` covers them.

## 4. Code conventions

### 4.1 Swift

Swift 6 language mode, complete strict concurrency, approachable concurrency, and warnings as errors; the package defaults to nonisolated. No `#available` or `@available` for older systems, no Combine, no `DispatchQueue` outside AppKit glue, no `print` outside the tools' output. Logging uses `os.Logger`, one subsystem per process (its bundle identifier), one category per module. Errors are typed `enum`s per module conforming to `LocalizedError`; user-visible text comes from the view layer. One primary type per file, extensions in `Type+Topic.swift`, a header comment naming the defining spec section. The package declares access control explicitly.

### 4.2 SwiftUI and AppKit

SwiftUI with `@Observable`, `@State`, `@Environment`, `@Bindable`; no `ObservableObject`. AppKit and UIKit only where SwiftUI has no equivalent, each use in one file under `TimeTracking/Platform/` or `TimeTrackingiOS/Platform/`.

### 4.3 Formatting and lint

SwiftFormat and SwiftLint run as Debug build phases of the two apps, from package checkouts, and in `make lint`. SwiftFormat rewrites sources (`.swiftformat`); SwiftLint fixes what it can and reports the rest (`.swiftlint.yml` opts into all rules, lists disabled ones with a reason, and has a custom rule against `#available` and `@available`). Zero warnings, zero SwiftLint findings.

## 5. Dependencies

System frameworks first; third-party packages are pinned exactly in the committed `Package.resolved` files.

The packages are `groue/GRDB.swift` 7.x (store, agent samples), `apple/swift-argument-parser` 1.x (the tool), `sindresorhus/KeyboardShortcuts` (the recordable shortcuts `showHideTimer` and `continueStop`), `LebJe/TOMLKit` (`settings.toml`, the description file), and the build-time tools `nicklockwood/SwiftFormat` and `SimplyDanny/SwiftLintPlugins`, which are not linked.

No networking, HTTP/2, JWT, Markdown, logging, or dependency-injection packages.

## 6. Repository layout

Source folders carry their target's name (1.3); `Packages/TimeTrackingCore/`, `Config/`, `Fixtures/`, `scripts/`, `spec/`, and `.githooks/` sit beside them, and build products go to `build.noindex/`. The `.gitignore` covers build output, `local.mk`, `Config/Local.xcconfig`, `.private-strings`, and key and profile files (`*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, `*.provisionprofile`).

## 7. Testable behaviors

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
12. Running `make check-behaviors` exits non-zero and lists `TM-999` when the Timer spec defines item 999 without a test; it also reports a test identifier that no spec defines and a non-continuous list.
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
