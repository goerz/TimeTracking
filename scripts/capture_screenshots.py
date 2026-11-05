#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pillow==12.0.0",
#     "pyobjc-framework-ApplicationServices",
#     "pyobjc-framework-Cocoa",
#     "pyobjc-framework-Quartz",
# ]
# ///
"""Captures the raw screenshots of the documentation site (architecture.md §2.7).

    scripts/capture_screenshots.py <raw folder> [name...]

Run it through `make screenshots`, which holds the runtime lock. Every app runs
with `-UITesting YES` and the store fixture `running`, at the test clock's
2024-03-14T10:00:00: the store and the calendars are in memory, so no real
data can appear and every run shows the same days. On the Mac the driver
(scripts/drive_mac_app.py) moves through the app and each image is one window,
captured by its id, so nothing else on the desktop shows. The one exception is
`mac-desktop`: real windows on a desktop drawn by scripts/compose_desktop.py,
since a real screen would show the owner's own menu bar and Dock. The Mac's
keyboard and pointer must be free meanwhile. The simulators get a fixed status bar and the
light appearance, and their tabs are chosen with `-PadTab`. The widgets are the
one exception to the in-memory store: they read the simulator's Debug store, so
it gets the same fixture, moved to today.

The images are named after their shots; scripts/frame_screenshots.py then puts
them into device frames. With names, only those shots run.
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

import AppKit
import Quartz
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compose_desktop  # noqa: E402
import drive_mac_app as app  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = "running"
MAIN_WINDOW_SIZE = (1360, 880)
DESKTOP_WINDOW_SIZE = (1190, 826)
# Short enough to fit between the open status menu and the Dock.
DESKTOP_TIMER_HEIGHT = 440
DESKTOP_CLOCK = "Thu Mar 14  10:00"
SIM_IPHONE = "TimeTracking iPhone"
SIM_IPAD = "TimeTracking iPad"
# Only for the README's image, so it exists only while that image is taken.
SIM_IPAD_MINI = "TimeTracking iPad mini"
IPAD_MINI_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPad-mini-A20-Pro"
WIDGETS = "iphone-widgets"


def settle(seconds=1.0):
    """Waits for a view to draw; the fixture's first load takes the longest."""
    time.sleep(seconds)


# MARK: Mac windows


def windows_on_screen():
    """The app's on-screen windows at any level, front to back, as dictionaries."""
    pid = app.checked_pid()
    info = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
    return [
        {
            "id": int(item["kCGWindowNumber"]),
            "layer": int(item["kCGWindowLayer"]),
            "bounds": dict(item["kCGWindowBounds"]),
        }
        for item in info
        if item["kCGWindowOwnerPID"] == pid and item["kCGWindowBounds"]["Height"] > 30
    ]


def window_named(identifier):
    """The AX window with an identifier: `planner`, `timer`, or None for the settings."""
    for element in app.windows():
        if element.identifier == identifier:
            return element
    raise app.DriverError(f"no window {identifier!r}")


def resize(element, size):
    value = app.AX.AXValueCreate(app.AX.kAXValueCGSizeType, Quartz.CGSizeMake(*size))
    app.AX.AXUIElementSetAttributeValue(element.ref, "AXSize", value)
    settle(0.5)


def cg_window(element):
    """The window id of an AX window, by its frame."""
    x, y, width, height = element.frame
    for window in windows_on_screen():
        bounds = window["bounds"]
        differences = (bounds["X"] - x, bounds["Y"] - y, bounds["Width"] - width, bounds["Height"] - height)
        if all(abs(difference) < 2 for difference in differences):
            return window
    raise app.DriverError(f"no window at {element.frame}")


def capture_id(window_id, path):
    subprocess.run(["screencapture", "-x", "-o", "-l", str(window_id), str(path)], check=True)


def capture(element, path):
    """Writes one window to `path`; a popover of the window comes along."""
    capture_id(cg_window(element)["id"], path)


def main_window():
    return window_named("planner")


def show_section(number):
    app.key(str(number), ["cmd"])
    settle()


def section(number):
    def shoot(path):
        show_section(number)
        capture(main_window(), path)

    return shoot


def draw_time_block(day, start, minutes, title, project):
    """Draws a time block at 72 points per hour, by the column of `day`."""
    x = app.find(f"calendar.events.{day}").center[0]
    # The label of 10:00 gives way to the now-line's, so measure from 08:00.
    y = app.find("calendar.hourLabel.480").center[1] + (start - 480) * 1.2
    app.drag((x, y), (x, y + minutes * 1.2))
    settle(0.5)
    app.click(app.find("calendar.block.title").center)
    app.type_text(title)
    app.click(app.find("calendar.block.project").center)
    settle(0.5)
    app.type_text(project)
    settle(0.5)
    app.key("return")
    settle(0.5)
    app.key("return")
    settle(0.5)


calendar_prepared = False


def prepare_calendar():
    """Shows the Calendar; the first time, also its zoom and its time blocks."""
    global calendar_prepared
    show_section(2)
    if calendar_prepared:
        return
    calendar_prepared = True
    # Wide enough for text on the activity cards, with two past days in view.
    app.key("]", ["opt", "cmd"])
    settle(0.5)
    app.key("t", ["cmd"])
    settle(0.5)
    app.key("left")
    settle()
    draw_time_block("2024-03-12", 600, 90, "Outline the methods", "Model paper")
    draw_time_block("2024-03-13", 540, 120, "Plan the methods", "Model paper")
    draw_time_block("2024-03-14", 660, 90, "Write the intro", "Model paper")
    draw_time_block("2024-03-14", 840, 90, "Review the slides", "Control paper")


def calendar(path):
    prepare_calendar()
    capture(main_window(), path)


def entry_popover(path):
    show_section(1)
    row = next(element for element in app.walk() if element.identifier.startswith("timer.row."))
    app.click(row.center)
    app.find("editor.task")
    settle(0.5)
    capture(main_window(), path)
    app.key("escape")
    settle(0.3)


def settings_pane(pane):
    def shoot(path):
        app.key(",", ["cmd"])
        settle()
        window = next(element for element in app.windows() if element.identifier not in ("planner", "timer"))
        tab = next(element for element in app.walk(window.ref) if element.label == pane and "Button" in element.role)
        app.click(tab.center)
        settle()
        window = next(element for element in app.windows() if element.identifier not in ("planner", "timer"))
        capture(window, path)
        app.key("w", ["cmd"])
        settle(0.3)

    return shoot


def mini_timer_window():
    app.press_menu("Window", "Mini Timer")
    settle()
    return window_named("timer")


def mini_timer(path):
    capture(mini_timer_window(), path)


def mini_timer_compact(path):
    mini_timer_window()
    app.key("m", ["cmd", "shift"])
    settle()
    capture(window_named("timer"), path)
    app.key("m", ["cmd", "shift"])
    settle(0.5)


def pomodoro(path):
    mini_timer_window()
    app.key("m", ["cmd", "shift"])
    settle()
    app.key("p", ["cmd", "shift"])
    settle()
    capture(window_named("timer"), path)
    app.key("p", ["cmd", "shift"])
    app.key("m", ["cmd", "shift"])
    settle(0.5)


def status_item():
    """The app's status item, from its menu bar extras."""
    bar = app.attribute(app.app_element(), "AXExtrasMenuBar")
    children = app.attribute(bar, "AXChildren") or []
    if not children:
        raise app.DriverError("the app has no status item")
    return app.wrap(children[0])


def menu_bar(path, item_path=None):
    """Captures the open status menu and, with `item_path`, the item above it."""
    item = status_item()
    known = {window["id"] for window in windows_on_screen()}
    app.click(item.center)
    settle()
    fresh = [window for window in windows_on_screen() if window["id"] not in known]
    if not fresh:
        raise app.DriverError("the status menu did not open")
    capture_id(fresh[0]["id"], path)
    if item_path:
        x, y, width, height = (round(value) for value in item.frame)
        subprocess.run(["screencapture", "-x", f"-R{x},{y},{width},{height}", str(item_path)], check=True)
    app.key("escape")
    settle(0.3)


def menu_titles():
    """The app's real menus, without the Apple menu."""
    bar = app.attribute(app.app_element(), "AXMenuBar")
    titles = [app.attribute(item, "AXTitle") for item in app.attribute(bar, "AXChildren") or []]
    return [title for title in titles[1:] if title]


def app_path():
    """The running app's bundle, for its icon in the Dock."""
    url = AppKit.NSWorkspace.sharedWorkspace().URLForApplicationWithBundleIdentifier_(debug_app_id())
    return url.path()


def desktop(path):
    window_path = path.with_suffix(".window.png")
    timer_path = path.with_suffix(".timer.png")
    menu_path = path.with_suffix(".menu.png")
    item_path = path.with_suffix(".item.png")
    # The main window first: the Mini Timer takes the keyboard when it opens.
    prepare_calendar()
    resize(main_window(), DESKTOP_WINDOW_SIZE)
    settle()
    app.key("t", ["cmd"])
    settle(0.5)
    app.key("left")
    settle()
    # The arrow key leaves a focus ring on the sidebar button; this clears it.
    app.click(main_window().point(0.07, 0.93))
    settle(0.5)
    capture(main_window(), window_path)
    resize(main_window(), MAIN_WINDOW_SIZE)
    settle()
    timer = mini_timer_window()
    timer_size = timer.frame[2:]
    resize(timer, (timer_size[0], DESKTOP_TIMER_HEIGHT))
    settle()
    capture(window_named("timer"), timer_path)
    resize(window_named("timer"), timer_size)
    menu_bar(menu_path, item_path)
    compose_desktop.compose(
        window_path,
        timer_path,
        menu_path,
        item_path,
        app_icon=app_path(),
        menus=menu_titles(),
        clock=DESKTOP_CLOCK,
        output=path,
    )
    for scratch in (window_path, timer_path, menu_path, item_path):
        scratch.unlink()


MAC_SHOTS = {
    "mac-timer": section(1),
    "mac-entry-popover": entry_popover,
    "mac-calendar": calendar,
    "mac-reports": section(3),
    "mac-projects": section(4),
    "mac-activity": section(5),
    "mac-settings-general": settings_pane("General"),
    "mac-settings-tracker": settings_pane("Tracker"),
    "mac-desktop": desktop,
    "mac-mini-timer": mini_timer,
    "mac-mini-timer-compact": mini_timer_compact,
    "mac-pomodoro": pomodoro,
    "mac-menu-bar": menu_bar,
}


def answer_idle_prompt():
    """Keeps the running entry if "You have been away" has come up."""
    if app.exists("idle.keep"):
        app.click(app.find("idle.keep").center)
        settle(0.5)


def capture_mac(names, raw):
    # Without full keyboard access, no focus ring sits on a toolbar button.
    app.launch(fixture=FIXTURE, calendar=True, extra=["-UITestingAppearance", "light", "-AppleKeyboardUIMode", "0"])
    try:
        resize(main_window(), MAIN_WINDOW_SIZE)
        # The idle check looks every 10 seconds, so a Mac left alone for a while
        # asks about it soon after the driver's first input. Answer that first.
        settle(12)
        for name in names:
            answer_idle_prompt()
            print(name, flush=True)
            MAC_SHOTS[name](raw / f"{name}.png")
    finally:
        answer_idle_prompt()
        app.quit_app()


# MARK: Simulators


def debug_app_id():
    return app.debug_bundle_id()


def simulator(name):
    return subprocess.run(
        [ROOT / "scripts/simulator.sh", "udid", name], capture_output=True, text=True, check=True
    ).stdout.strip()


def simctl(*arguments, env=None):
    subprocess.run(["xcrun", "simctl", *arguments], check=True, env=env)


def prepare_simulator(udid):
    """A clean status bar at the fixture's time, in the light appearance."""
    simctl("bootstatus", udid, "-b")
    simctl("ui", udid, "appearance", "light")
    simctl(
        "status_bar", udid, "override",
        "--time", datetime.fromisoformat(app.FIXED_NOW).astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "notSupported",
        "--batteryState", "charged", "--batteryLevel", "100",
    )  # fmt: skip


def launch_on_simulator(udid, *arguments):
    environment = dict(os.environ, SIMCTL_CHILD_TIMETRACKING_NOW=app.FIXED_NOW)
    simctl(
        "launch", "--terminate-running-process", udid, debug_app_id(),
        "-UITesting", "YES", "-Fixture", FIXTURE, *arguments,
        env=environment,
    )  # fmt: skip
    settle(4)


def rotate_to_landscape(udid):
    subprocess.run(["xcrun", "devicectl", "device", "orientation", "set", "--device", udid, "landscapeLeft"], check=True)
    settle(2)


def create_ipad_mini():
    """A temporary iPad mini in landscape, with the app `make sim` just built."""
    created = subprocess.run(
        ["xcrun", "simctl", "create", SIM_IPAD_MINI, IPAD_MINI_TYPE], capture_output=True, text=True, check=True
    )
    udid = created.stdout.strip()
    simctl("boot", udid)
    prepare_simulator(udid)
    built = (ROOT / "build.noindex/Build/Products/Debug-iphonesimulator").glob("*.app")
    simctl("install", udid, str(next(app for app in built if "Runner" not in app.name)))
    rotate_to_landscape(udid)
    return udid


def cover_status_date(path, left=134, background_at=(600, 30)):
    """Clears the iPad status bar's weekday, date, and app name beside the
    clock: the override's date always reads as a Tuesday, against the Thursday
    the app shows."""
    image = Image.open(path).convert("RGBA")
    background = image.getpixel(background_at)
    ImageDraw.Draw(image).rectangle((left, 8, 560, 58), fill=background)
    image.save(path)


# name: (simulator, launch arguments, a URL to open after the launch)
IOS_SHOTS = {
    "iphone-timer": (SIM_IPHONE, (), None),
    "ipad-timer": (SIM_IPAD, ("-PadTab", "timer"), None),
    "ipad-calendar": (SIM_IPAD, ("-PadTab", "calendar"), "planner/calendar?date=2024-03-11"),
    "ipad-reports": (SIM_IPAD, ("-PadTab", "reports"), None),
    "ipad-mini-reports": (SIM_IPAD_MINI, ("-PadTab", "reports"), None),
}


def seed_widget_data(udid):
    """Widgets read the store on disk, so the simulator's Debug store gets the
    fixture, and the shared settings say that setup is complete."""
    identifier = debug_app_id()
    group = subprocess.run(
        ["xcrun", "simctl", "get_app_container", udid, identifier, f"group.{identifier}"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()  # fmt: skip
    simctl("terminate", udid, identifier)
    subprocess.run(
        ["swift", "run", "--quiet", "--package-path", ROOT / "Packages/TimeTrackingCore", "DemoStore", FIXTURE,
         f"{group}/Library/Application Support/TimeTracking/store.sqlite"],
        check=True,
    )  # fmt: skip
    preferences = Path(group) / "Library/Preferences" / f"group.{identifier}.plist"
    preferences.parent.mkdir(parents=True, exist_ok=True)
    if not preferences.exists():
        subprocess.run(["plutil", "-create", "binary1", preferences], check=True)
    subprocess.run(["plutil", "-replace", "setupComplete", "-bool", "YES", preferences], check=True)
    simctl("shutdown", udid)
    prepare_simulator(udid)


def iphone_widgets(udid, path):
    """Adds the widgets with a UI test, since no command can, and shoots the Home Screen."""
    seed_widget_data(udid)
    subprocess.run(
        ["xcodebuild", "-quiet", "-project", "TimeTracking.xcodeproj", "-derivedDataPath", "build.noindex",
         "-skipPackagePluginValidation", "-skipMacroValidation", *os.environ.get("XCFLAGS", "").split(),
         "test", "-scheme", "TimeTrackingiOS", "-destination", f"platform=iOS Simulator,id={udid}",
         "-only-testing:TimeTrackingiOSUITests/WidgetScreenshotUITests",
         "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration"],
        cwd=ROOT, check=True, env=dict(os.environ, TEST_RUNNER_TIMETRACKING_SCREENSHOTS="1"),
    )  # fmt: skip
    settle(8)
    simctl("io", udid, "screenshot", str(path))


def capture_simulators(names, raw):
    subprocess.run(["make", "--no-print-directory", "sim", "ARGS=-UITesting YES"], cwd=ROOT, check=True)
    devices = {name: simulator(name) for name in (SIM_IPHONE, SIM_IPAD)}
    for udid in devices.values():
        prepare_simulator(udid)
    rotate_to_landscape(devices[SIM_IPAD])
    mini = None
    if any(IOS_SHOTS.get(name, (None,))[0] == SIM_IPAD_MINI for name in names):
        mini = devices[SIM_IPAD_MINI] = create_ipad_mini()
    try:
        for name in names:
            print(name, flush=True)
            if name == WIDGETS:
                iphone_widgets(devices[SIM_IPHONE], raw / f"{name}.png")
                continue
            device, arguments, url = IOS_SHOTS[name]
            launch_on_simulator(devices[device], *arguments)
            if url:
                simctl("openurl", devices[device], f"timetracking-debug://{url}")
                settle(2)
            path = raw / f"{name}.png"
            simctl("io", devices[device], "screenshot", str(path))
            if device == SIM_IPAD:
                cover_status_date(path)
            elif device == SIM_IPAD_MINI:
                # Landscape shows the sidebar under the status bar's date.
                cover_status_date(path, left=150, background_at=(20, 30))
    finally:
        subprocess.run(["xcrun", "devicectl", "device", "orientation", "set", "--device", devices[SIM_IPAD], "portrait"])
        for udid in devices.values():
            simctl("status_bar", udid, "clear")
            subprocess.run(["xcrun", "simctl", "terminate", udid, debug_app_id()], stderr=subprocess.DEVNULL)
        if mini:
            subprocess.run(["xcrun", "simctl", "shutdown", mini], check=False)
            simctl("delete", mini)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("raw", type=Path, help="the folder for the raw images")
    parser.add_argument("names", nargs="*", help="the shots to take; default all")
    args = parser.parse_args()
    known = [*MAC_SHOTS, *IOS_SHOTS, WIDGETS]
    names = args.names or known
    if unknown := sorted(set(names) - set(known)):
        parser.error(f"unknown shots {json.dumps(unknown)}; known: {', '.join(known)}")
    args.raw.mkdir(parents=True, exist_ok=True)
    try:
        if mac := [name for name in names if name in MAC_SHOTS]:
            capture_mac(mac, args.raw)
        if ios := [name for name in names if name in IOS_SHOTS or name == WIDGETS]:
            capture_simulators(ios, args.raw)
    except app.DriverError as error:
        print(f"capture_screenshots: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
