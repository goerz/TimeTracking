# TimeTracking

A personal time tracker for the Mac, iPhone, and iPad. Start with `spec/components.md` (components, vocabulary, cross-cutting rules), then the component spec for the area you work on. This file condenses the conventions of `spec/spec_architecture.md`; the spec wins where they differ.

## Layout and what each target holds

One Xcode project (`TimeTracking.xcodeproj`, hand-authored, file-system-synchronized groups) and one local package (`Packages/TimeTrackingCore`) linked statically by every executable. There is no workspace and no XcodeGen.

| Folder | Holds |
|---|---|
| `Packages/TimeTrackingCore` | All logic: `Model/`, `Store/`, `Sync/`, `Push/`, `Queries/`, `Interchange/`, `Activity/`, `TimeBlocks/`, `Suggestions/`, `Intents/`, `Support/`. Never imports SwiftUI, AppKit, UIKit, or WidgetKit. |
| `TimeTracking/` | Mac app: scenes (main window, Mini Timer), Timer, `MainWindow/`, status item, settings, agent registration, global shortcuts, AppKit glue in `Platform/`, URL handler, `LiveStatePublisher` and `WidgetPushSender` |
| `TimeTrackingiOS/` | iOS app: scenes, Timer tab, iPad tabs, background refresh and silent pushes, widget push token upload, URL handler |
| `Shared/` | Views compiled into both apps; platform differences are `#if os(macOS)` around a modifier |
| `WidgetShared/`, `CollectionShared/` | Code compiled into the iOS app and the widget extension, and into the iOS app and the monitor extension |
| `AppResources/` | The app icon (`AppIcon.icon`) and the `AccentColor` asset, in the Mac app, the agent, and the iOS app (`spec_design.md` §9) |
| `TimeTrackingAgent/` | The tracker login item (`LSUIElement`; flags `--record`, `--replay`, `--unregister`) |
| `TrackerEvent/` | `tracker-event`: one line to the agent's socket; links only Foundation |
| `TimeTrackingCLI/` | `timetracking`: argument parsing and output only; never touches CloudKit |
| `TimeTrackingWidgets/`, `TimeTrackingIntents/`, `TimeTrackingMonitor/`, `TimeTrackingWebExtension/` | iOS extensions: rendering and forwarding only |
| `*Tests/`, `*UITests/` | Test bundles (see Testing) |
| `AppTestSupport/` | Test helpers compiled into both hosted test bundles (`TimeTrackingTests`, `TimeTrackingiOSTests`) |
| `Config/` | `Project.xcconfig`, `<target>.entitlements`, `<target>-Info.plist` |
| `Fixtures/` | `Store/<name>.json` (export format), `Activity/`, `Agent/`; synthetic, dates in 2024 |
| `scripts/` | `check_behaviors.sh`, `test_make.sh`, `check_products.sh`, `install.sh`, `apns_key.sh`, `debug_unregister.sh`, `simulator.sh` (simulator UDID by name, Device Hub), `relaunch_mac_app.sh` (mac-debug's quit and reopen), `common.sh` (shared by the install and unregister scripts), lint helpers |

A view model may hold selection, drafts, sort order, and presentation state and call the library. It may not compute totals, overlaps, or export formats. If a view model test needs a store fixture, the logic belongs in the library.

## Identifiers (spec_architecture.md §1.5)

Everything derives from `TT_APP_ID`: `<BUNDLE_ID>` in Release, `<BUNDLE_ID>.debug` in Debug, on both platforms. Debug has its own containers, so development never touches real data.

| Identifier | Value |
|---|---|
| Agent | `<APP_ID>.agent`, launchd plist `Contents/Library/LaunchAgents/<APP_ID>.agent.plist`; bundle `TimeTrackingAgent.app`, Debug `TimeTrackingAgent Debug.app` |
| Extensions | `<APP_ID>.widgets`, `.intents`, `.monitor`, `.web-extension` |
| App Group | iOS `group.<APP_ID>`; Mac `<TEAM>.<APP_ID>` |
| CloudKit and ubiquity container | `iCloud.<APP_ID>` |
| Change notification | `<APP_ID>.changed` (the only cross-process change signal) |
| Store | `<Mac group container>/Library/Application Support/TimeTracking/store.sqlite` |
| Agent socket | same folder, `tracker.sock` (the full path exceeds the 104-byte `sun_path`; connect relative to the folder) |
| URL scheme | `timetracking`, Debug `timetracking-debug` |
| Widget push topic | `<APP_ID>.push-type.widgets` |
| APNs key Keychain service | `<BUNDLE_ID>.apns` (shared by Release and Debug) |

Code reads these through `AppIdentity.main` (from the `TT*` Info.plist keys: `TTAppID`, `TTBundleID`, `TTTeamID`, `TTAppGroup`, `TTCloudKitContainer`, `TTURLScheme`). The two tools carry their Info.plist inside the binary. Never hard-code an identifier.

## Personal settings and the xcconfig (§2.1, §2.2)

Nothing personal is committed. `local.mk` (git-ignored; template `local.mk.example`) holds `TEAM`, `BUNDLE_ID`, `APP_NAME`, `DEVICE_<name>`, `PREFIX`, `ALIAS`. Every building make target first writes `Config/Local.xcconfig` (git-ignored) with `TT_BUNDLE_ID`, `TT_APP_NAME`, and `DEVELOPMENT_TEAM`, only when the content changes.

`Config/Project.xcconfig` is the only place for identifiers and signing. No target in the project file sets `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`, `CODE_SIGN_*`, `PROVISIONING_PROFILE*`, or `PRODUCT_NAME`; per-target values come from tables keyed by `TARGET_NAME` (`TT_BUNDLE_IDENTIFIER_<target>`, `TT_PRODUCT_NAME_<target>`, `TT_PRODUCT_<target>`). The apps' `PRODUCT_NAME` is `$(TT_APP_NAME)`; module and executable names stay `TimeTracking`, `TimeTrackingiOS`, and `TimeTrackingAgent`. In Debug the Mac bundles are `<APP_NAME> Debug.app` and `TimeTrackingAgent Debug.app` (`TT_MAC_APP_NAME`, `TT_AGENT_NAME`; their `CFBundleName` and `CFBundleDisplayName` follow), because System Settings (Privacy & Security, Login Items) and Finder show bundle file names; every Debug display name ends in " Debug". Never hard-code a Debug bundle path: use those settings, the Makefile's `MAC_DEBUG_APP` and `DEBUG_AGENT`, or list `Contents/Library/LoginItems`. Swift 6.0 language mode, complete strict concurrency, approachable concurrency, member import visibility, warnings as errors, `MainActor` default isolation for shipping products (the package and test bundles default to nonisolated). Mac targets are unsandboxed with the hardened runtime; Release Mac builds carry no `get-task-allow`. Deployment targets are macOS 27.0 and iOS 27.0.

## Building

Always use the Makefile; it sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the default `xcode-select` points at the Command Line Tools). `make help` lists everything. Common targets:

| Command | Does |
|---|---|
| `make build-mac` | Release Mac app with agent and tools, then `scripts/check_products.sh` (bundle layout, entitlements, hardened runtime, launchd plist) |
| `make build-ios` / `make build-sim` | Release iOS for devices / Debug for the "TimeTracking iPhone" simulator |
| `make mac-debug` | Debug Mac app (`<APP_NAME> Debug.app`) from `build.noindex/`; quits a running Debug app first, so the new build is the one that runs |
| `make demo [FIXTURE=small]` | The store fixture (`small`, `large`, `running`) moved to today into the Debug store and both simulators' stores, then the Debug Mac app and simulators launched; Debug containers only |
| `make sim` | Build, install, and launch on both simulators; show them in Device Hub |
| `make install` | Install into `/Applications`, link `timetracking` and `tracker-event` into `$(PREFIX)/bin`, write completions |
| `make lint` | SwiftFormat `--lint` and SwiftLint `--strict`; no build |

Every `xcodebuild` call uses `-quiet -project TimeTracking.xcodeproj -derivedDataPath build.noindex -skipPackagePluginValidation -skipMacroValidation` and, when signing, `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`. All builds are development-signed with automatic provisioning: APNs sandbox and the CloudKit development environment in Release and Debug alike. `XCFLAGS` passes extra build settings to every `xcodebuild` call.

Simulator destinations are UDIDs looked up by name (`scripts/simulator.sh udid "TimeTracking iPhone"`), never `name=`. Read `docs/xcode27.md` when working with simulators, destinations, Device Hub, test results, or other Xcode 27 command-line tooling.

## Extending the project

- New source file: put it in the target's folder. The folders are synchronized groups, so the project file does not change. Files in a folder belong to every target that lists the folder (`Shared/` is in both apps).
- New folder with its own target membership, a new build phase, a new target, or a package dependency: edit `project.pbxproj` minimally, by hand, then check with `xcodebuild -list` and a build.
- New target: add a `PBXNativeTarget` with its own `XCConfigurationList` (both configurations use `Project.xcconfig` as base and set only `SDKROOT`, `SUPPORTED_PLATFORMS`, and test-host settings), a `PBXFileSystemSynchronizedRootGroup` for its folder (also listed in the main group), a product `PBXFileReference` in the Products group, and its entry in the project's `targets` and `TargetAttributes`. Add its rows to the tables in `Project.xcconfig` (bundle identifier; `TT_PRODUCT_<target> = YES` for a shipping product, which then needs `Config/<target>.entitlements` and `Config/<target>-Info.plist`). Embed it with a copy phase of its host and add it to a shared scheme in `xcshareddata/xcschemes/` if the Makefile runs it. Add its folder to `scripts/lint_paths.sh`.
- New package dependency: add an `XCRemoteSwiftPackageReference` with `kind = exactVersion`, an `XCSwiftPackageProductDependency` and a `PBXBuildFile` in the target's Frameworks phase; resolve with `xcodebuild -resolvePackageDependencies` and commit the updated `TimeTracking.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. A dependency of the library goes into `Packages/TimeTrackingCore/Package.swift` with `exact:` instead (and its `Package.resolved`). Only the packages of §5 are allowed.

## Testing (§3)

| Kind | Framework | Where | Command |
|---|---|---|---|
| Library | Swift Testing | `Packages/TimeTrackingCore/Tests/TimeTrackingCoreTests` | `swift test --package-path Packages/TimeTrackingCore` |
| Mac view models | Swift Testing, hosted in the Debug app | `TimeTrackingTests` | part of `make unit-test` |
| Agent | Swift Testing, hosted in the agent | `TimeTrackingAgentTests` | `make agent-test` |
| Tools | Swift Testing, tools as subprocesses | `TimeTrackingCLITests` | part of `make unit-test` |
| iOS view models | Swift Testing, iPhone simulator | `TimeTrackingiOSTests` | part of `make test` |
| UI | XCTest (XCUITest) | `TimeTrackingUITests`, `TimeTrackingiOSUITests` (iPhone and iPad) | `make ui-test` |
| Makefile, scripts, hooks | shell | `scripts/test_make.sh` (`--build`, `--products`, `--sim`, `--install`) | `scripts/test_make.sh` |
| CloudKit integration | Swift Testing, `.tags(.sync)` | enabled only by `TIMETRACKING_TEST_SYNC=1` | `make test-sync`, never part of `make test` |

Every numbered item in a spec's "Testable behaviors" is backed by a test carrying its identifier (`ARCH`, `DATA`, `TM`, `MB`, `PP`, `PC`, `PR`, `PA`, `TRK`, `IOS`, `AUTO`): in a Swift Testing display name, `@Test("TM-1 releasing below 200 pt collapses to the bar")`; in an XCUITest method name, `testTM1_collapseBelowThreshold()`; in `scripts/test_make.sh`, `behavior "ARCH-2 ..."`. One test may name several. `make check-behaviors` (optionally `ONLY=TM,MB`) fails on a behavior without a test, an identifier no spec defines, or a non-continuous list.

Rules: `make test` needs no network and no permission grant; it uses the in-memory store and transport only. UI tests find controls by accessibility identifier (`timer.startButton`), never by visible text, and launch with `-UITesting YES` (in-memory store and transport, a fake agent service, `-Fixture <name>`, no animations), which may not change what a control does. Only the ARCH-8 UI tests add `-RealAgent YES` to register the real Debug agent, and they unregister it again. Tests never sleep: use `ManualClock`, drive the agent's tick, fix `TIMETRACKING_NOW`. The test clock is `ManualClock.fixture()`, 2024-03-14T10:00:00 local time. A test over 10 seconds is tagged `.slow`.

## Code conventions (§4)

- Swift 6, complete strict concurrency, zero warnings, zero SwiftLint findings. Current platforms only: no `#available` or `@available` (a SwiftLint custom rule enforces it), no Combine, no `DispatchQueue` outside AppKit glue, no `print` outside the tools' output.
- Logging through `Logging.logger(category:)` (`os.Logger`): one subsystem per process (its bundle identifier), one category per module.
- Errors are typed `enum`s per module conforming to `LocalizedError`; user-visible text comes from the view layer.
- One primary type per file; extensions in `Type+Topic.swift`; every file starts with a header comment naming its defining spec section. The package declares access control explicitly. Time comes from a `Clock` (`SystemClock`, `ManualClock`), never from `Date()` in logic.
- SwiftUI with `@Observable`, `@State`, `@Environment`, `@Bindable`; no `ObservableObject`. Observed library types are `@MainActor @Observable`; the store and sync coordinator are actors; model values are `Sendable` structs. AppKit only where SwiftUI has no equivalent, one file per use under `TimeTracking/Platform/`. UIKit is not expected.
- SwiftFormat (`.swiftformat`: indent 4, upper-case acronyms, trailing commas, `self` only in initializers) and SwiftLint (`.swiftlint.yml`: all rules, disabled ones listed with a reason) run as Debug build phases of both apps, from the package checkouts, and in `make lint`.

## Dependencies (§5)

System frameworks first. Third-party packages, pinned exactly in the committed `Package.resolved` files: GRDB.swift 7.x (store, agent samples), swift-argument-parser 1.x (the tool), KeyboardShortcuts (`showHideTimer`, `continueStop`, in `Platform/GlobalShortcuts.swift`), TOMLKit (`settings.toml`, the automation description file), SwiftFormat and SwiftLintPlugins (build-time tools, not linked). No networking, HTTP/2, JWT, Markdown, logging, or dependency-injection packages.

## Git

Hooks in `.githooks/` (enabled by `make hooks`, which every building target runs) refuse personal data: the `local.mk` values, `.private-strings` lines, the home directory, host names, the git e-mail, credentials, UDIDs, and key or profile files (`make check-private`). The pre-push hook also runs `make lint`. Never bypass a hook.

## Parallel sessions

Several Claude sessions often work on this repository at once. Every session that will edit files starts by calling EnterWorktree (one worktree per task, named after it, without `/`), then runs `ln -s ../../../local.mk local.mk` in the worktree before the first `make`. Read-only sessions stay in the main checkout.

Commit on the worktree branch. When the task is done, committed, and its tests pass, ask the user (AskUserQuestion) whether to merge it into `master`; don't wait to be asked, and don't merge without a yes. On yes: in the worktree, `git rebase master` (resolve conflicts, rerun the affected tests); then ExitWorktree with `keep`, and in the main checkout `git merge --ff-only <branch>`. If the fast-forward refuses because the main checkout's uncommitted changes touch the same files, stop and report rather than stashing someone else's work. After the merge, ask whether to remove the worktree and its branch (`git worktree remove`, `git branch -d`).

Worktrees isolate source, not runtime state: all checkouts share the Debug bundle ID, the Debug store, the Debug agent registration, the simulators, and `/Applications`. The Makefile serializes `sim`, `mac-debug`, `demo`, `install`, `unit-test`, `agent-test`, `ui-test`, `test`, and `test-sync` across checkouts with a lock in the shared git directory: while one checkout runs any of them, the others fail with "another checkout is running ..." (`Error 75`). On that message, wait for the other session (SendMessage with `notify_when_idle` to the session ListAgents shows) and rerun; never work around the lock with a bare `xcodebuild`, `xcrun simctl`, or `open` of the Debug app. `swift test --package-path Packages/TimeTrackingCore` and `make lint` don't take the lock.
