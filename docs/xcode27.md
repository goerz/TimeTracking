# Xcode 27 command-line notes

Reference notes for sessions that build, run, or test this project from the command line. Checked on 2026-10-31 with Xcode 27.2 (27B52) on macOS 27.0.1, SDK `iphonesimulator27.2`, runtimes iOS 27.0, iOS 27.2, and "iOS 27.2 iPhone19-4". "Local" means observed on this machine; anything marked unverified comes from a third-party report only.

## Simulator.app is gone; Device Hub replaces it

Xcode 27 removed Simulator.app. `open -a Simulator` fails with "Unable to find application named 'Simulator'" (local), and `Xcode.app/Contents/Developer/Applications/` no longer exists. The replacement is `Xcode.app/Contents/Applications/DeviceHub.app` (bundle id `com.apple.dt.Devices`, alternate names "Devices" and "Device Hub"), one window that lists simulators and physical devices in a sidebar and shows the selected one ([Bitrise](https://bitrise.io/blog/post/wwdc-2026-device-hub-and-what-it-means-for-ci-cd), [Michael Tsai](https://mjtsai.com/blog/2026/06/25/xcode-27s-device-hub/), [Apple: Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)).

Device Hub has no command-line tool. It registers the URL scheme `devices` (its Info.plist, local), and the routes live in `Xcode.app/Contents/SharedFrameworks/DeviceKit.framework` (`DeviceURLActionProvider`, `DeviceManagementURLActionProvider`, actions `open`, `select`, `showInspector`). To show a simulator:

```sh
open -a "$DEVELOPER_DIR/../Applications/DeviceHub.app" "devices://device/open?id=<UDID>"
```

Locally, both `devices://device/open?id=<UDID>` and `devices://manage/select?id=<UDID>` log "successfully handled by provider" in the DeviceKit `URLAction` log category, and an unknown route logs "No URL action provider was able to handle URL". Expo's CLI uses `device/open` to focus a device and falls back to `open -a DeviceHub` ([Expo](https://expo.dev/blog/xcode-27-device-hub-expo-device-hub)); a Tuist issue mentions `manage/select` (tuist/tuist #12740, unverified). Boot with simctl first; whether the URL boots a shut-down device is unverified. In this repository `scripts/simulator.sh show <name>...` does this, and falls back to Simulator.app on an older Xcode.

Simulator features that moved or vanished: slow animations, shake, and memory warnings, missing from Device Hub 27.0, are back in 27.2 (simulators only); CarPlay is not supported on simulators; dragging files onto a device does not work ([Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes), [Michael Tsai](https://mjtsai.com/blog/2026/06/25/xcode-27s-device-hub/)). Keyboard input goes to the device or to Device Hub according to `defaults -container com.apple.dt.Devices write com.apple.dt.Devices hostKeybindingPolicy -int 0|1|2` ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)). Parallel test clones may not appear in Device Hub while tests run (same notes). Device Hub may leave CoreSimulator processes running after it quits; "Shut Down" from a device's context menu, or `xcrun simctl shutdown <UDID>`, stops them (Michael Tsai, unverified).

## xcodebuild destinations: use the UDID

`-destination 'platform=iOS Simulator,name=<name>'` without `OS=` means `OS=latest`, "the most recent version of iOS supported by this version of Xcode" (`man xcodebuild`, Destinations). With Xcode 27.2 that is 27.2, so a device on the iOS 27.0 runtime does not match. Locally, `name=TimeTracking iPhone` (iOS 27.0) fails with "Unable to find a device matching the provided destination specifier" every time, `name=TimeTracking iPhone,OS=27.0` works, and `name=iPhone 17` silently picks the iOS 27.2 one of two same-named devices. The intermittent success seen earlier most likely dates from before the 27.2 runtime was installed (unverified).

`id=<UDID>` always resolves, on any installed runtime. This project therefore looks the UDID up by name at run time with `scripts/simulator.sh udid <name>` (parses `xcrun simctl list devices available`; the newest runtime wins when a name exists twice) and passes `platform=iOS Simulator,id=<UDID>`. Never commit a UDID; the git hooks refuse physical-device UDIDs, and simulator UDIDs differ per machine anyway. `generic/platform=iOS Simulator` also works for a build that installs nowhere, but it builds every simulator architecture instead of the active one.

`xcodebuild -showdestinations -scheme TimeTrackingiOS` lists only a subset of the installed iOS simulators here (the two TimeTracking devices, not the stock "iPhone 18 Pro" and others); do not rely on it to prove that a device exists. `xcodebuild -showBuildSettings -destination <spec>` is a quick way to test whether a destination resolves (it prints `TARGET_DEVICE_IDENTIFIER` and `TARGET_DEVICE_OS_VERSION`) without building.

## simctl

`xcrun simctl help` documents a device argument only as "a device UDID or the special booted string". Names still work locally, but with duplicate names (the same name on two runtimes) the choice is not defined, so pass the UDID. New in Xcode 27: `simctl reboot <device>` ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), Simulator). `simctl upgrade <device> <runtime>` moves a device to a newer runtime. `simctl bootstatus <device> -b` boots and waits until the device is up; it works although `simctl help` does not list it. Use it instead of `simctl boot` before `install`.

`simctl create <name> <device type>` without a runtime picks "the newest runtime compatible with the device type" (`simctl help create`). Prefer that to choosing a runtime from `simctl list runtimes`: the last iOS line there is now a device-specific runtime ("iOS 27.2 iPhone19-4", for the iPhone Duo only) that cannot run an iPhone 17 Pro or an iPad. `simctl list runtimes -j` shows `supportedDeviceTypes` per runtime. Known 27.2 issue: cloning a device on runtime 27.2 can fail on file permissions ([Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)).

## devicectl

`xcrun devicectl list devices` now lists simulators next to physical devices, with a "Reality" column (`physical` or `simulated`); `make devices` filters with `--filter "Reality = 'physical'"` (local). Tools that treat every devicectl device as hardware break on this ([Expo](https://expo.dev/blog/xcode-27-device-hub-expo-device-hub)). devicectl gained simulator commands without a simctl equivalent, such as `device orientation`, `device process sendMemoryWarning`, and `device appResize` for iPad ([Bitrise](https://bitrise.io/blog/post/wwdc-2026-device-hub-and-what-it-means-for-ci-cd)). `--json-output -` writes JSON to stdout; JSON version 5 deprecates `hardwareProperties`, `deviceProperties`, and `connectionProperties` in favor of `properties`; `device info details --show` is gone ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), devicectl).

## Testing and results

Xcode 27 ships Swift 6.4. Test-related changes in the release notes: a UI-test crash severity setting in test plans (off, warning, failure, fatal failure), a runtime warning when an XCTest assertion fails inside a Swift Testing test or the reverse, `XCUIVoiceOverService`, and `swift test --maximum-repetitions` with `--repeat-until pass|fail` ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), Testing and Swift Package Manager). Nothing in the notes changes `-only-testing`, multiple `-destination` arguments, or result bundles.

`xcresulttool` (version 25407 locally) uses structured commands: `xcrun xcresulttool get test-results summary|tests|test-details|activities|insights|metrics --path <bundle>`, `get build-results`, `get log`, plus `export`, `merge`, `compare`, and `metadata`. `graph`, `formatDescription`, and `get object` are deprecated, and `get object` needs `--legacy` (`xcresulttool help`, local). Pass `-resultBundlePath <path>` to `xcodebuild test` to keep a bundle; a failing call without it writes one under `$TMPDIR` and prints the path (local).

XCUITest on iPadOS: a forum report says the iPadOS 26 menu bar's items do not appear in the XCUIAutomation element tree although the same tests pass on macOS ([Apple Developer Forums 818842](https://developer.apple.com/forums/thread/818842), unverified on 27). This project's iPad UI tests drive the menu commands through `typeKey` shortcuts, which avoids the question. Device Hub sends Mac trackpad and mouse gestures to iOS as touches and scroll events, which differs from a real pointer; that matters only for manual testing (Xcode 27 release notes, Device Hub).

## Other changes worth knowing

- Xcode 27.2 adds an optional JSON project format (`.xcproj`, set in the File inspector). This project keeps `project.pbxproj`; converting would change the hand-editing rules in CLAUDE.md ([Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)).
- The Swift dependency scanner now errors when two module maps visible to one scan declare the same Clang module name (Xcode 27 release notes, Swift Compiler).
- A computed property with an `init` accessor and a literal initial value no longer compiles when the getter comes first (SE-0508; same section).
- Xcode's MCP server can run without an open workspace (`xcrun mcp-server enable`, preview), and `xcrun mcpbridge run-agent skills export` (used by `make skills`) still exists locally.
- Xcode 27 needs macOS 26.6 or later and runs only on Apple silicon; with a macOS 27 deployment target, `ARCHS_STANDARD` no longer includes x86_64 (Xcode 27 release notes, Intel Deprecation).
