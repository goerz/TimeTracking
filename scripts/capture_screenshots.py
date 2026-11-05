#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pillow==12.0.0",
#     "pyobjc-framework-ApplicationServices",
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
captured by its id, so nothing else on the desktop shows. The Mac's keyboard and
pointer must be free meanwhile. The simulators get a fixed status bar and the
light appearance, and their tabs are chosen with `-PadTab`.

The images are named after their shots; scripts/frame_screenshots.py then puts
them into device frames. With names, only those shots run.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import Quartz
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drive_mac_app as app  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = "running"
MAIN_WINDOW_SIZE = (1360, 880)
SIM_IPHONE = "TimeTracking iPhone"
SIM_IPAD = "TimeTracking iPad"


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
        if (abs(bounds["X"] - x), abs(bounds["Y"] - y), abs(bounds["Width"] - width), abs(bounds["Height"] - height)) < (
            2,
            2,
            2,
            2,
        ):
            return window
    raise app.DriverError(f"no window at {element.frame}")


def capture_id(window_id, path):
    subprocess.run(["screencapture", "-x", "-o", "-l", str(window_id), str(path)], check=True)


def capture(element, path, overlays=False):
    """Writes one window to `path`. With `overlays`, the app's windows in front
    of it (a popover, a popup) are composed onto it, each from its own capture."""
    base = cg_window(element)
    capture_id(base["id"], path)
    if not overlays:
        return
    canvas = Image.open(path).convert("RGBA")
    scale = canvas.width / base["bounds"]["Width"]
    above = []
    for window in windows_on_screen():
        if window["id"] == base["id"]:
            break
        above.append(window)
    for window in reversed(above):
        with tempfile.TemporaryDirectory() as folder:
            part = Path(folder) / "part.png"
            capture_id(window["id"], part)
            image = Image.open(part).convert("RGBA")
        x = round((window["bounds"]["X"] - base["bounds"]["X"]) * scale)
        y = round((window["bounds"]["Y"] - base["bounds"]["Y"]) * scale)
        canvas.alpha_composite(image, (max(x, 0), max(y, 0)))
    canvas.save(path)


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


def calendar(path):
    show_section(2)
    today = next(
        (element for element in app.walk() if element.identifier.startswith("calendar.events.2024-03-14")),
        None,
    )
    if today is None:
        raise app.DriverError("today's Calendar column is not in view")
    for start, title in ((780, "Write the intro"), (960, "Review the slides")):
        label = app.find(f"calendar.hourLabel.{start}")
        x = today.center[0]
        y = label.center[1]
        app.drag((x, y), (x, y + 120))
        settle(0.5)
        app.click(app.find("calendar.block.title").center)
        app.type_text(title)
        app.key("return")
        settle(0.5)
    capture(main_window(), path)


def entry_popover(path):
    show_section(1)
    row = next(element for element in app.walk() if element.role == "AXRow" and element.frame[1] > 0)
    app.click(row.center)
    app.find("editor.task")
    settle(0.5)
    capture(main_window(), path, overlays=True)
    app.key("escape")
    settle(0.3)


def settings_pane(pane):
    def shoot(path):
        app.key(",", ["cmd"])
        settle()
        app.click(app.find(f"settings.pane.{pane}").center)
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


def menu_bar(path):
    item = status_item()
    known = {window["id"] for window in windows_on_screen()}
    app.click(item.center)
    settle()
    fresh = [window for window in windows_on_screen() if window["id"] not in known]
    if not fresh:
        raise app.DriverError("the status menu did not open")
    capture_id(fresh[0]["id"], path)
    app.key("escape")
    settle(0.3)


MAC_SHOTS = {
    "mac-timer": section(1),
    "mac-entry-popover": entry_popover,
    "mac-calendar": calendar,
    "mac-reports": section(3),
    "mac-projects": section(4),
    "mac-activity": section(5),
    "mac-settings-general": settings_pane("general"),
    "mac-settings-tracker": settings_pane("tracker"),
    "mac-mini-timer": mini_timer,
    "mac-mini-timer-compact": mini_timer_compact,
    "mac-pomodoro": pomodoro,
    "mac-menu-bar": menu_bar,
}


def capture_mac(names, raw):
    app.launch(fixture=FIXTURE, calendar=True, extra=["-UITestingAppearance", "light"])
    try:
        resize(main_window(), MAIN_WINDOW_SIZE)
        for name in names:
            print(name, flush=True)
            MAC_SHOTS[name](raw / f"{name}.png")
    finally:
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
        "--time", app.FIXED_NOW,
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--cellularMode", "active", "--cellularBars", "4", "--operatorName", "",
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


IOS_SHOTS = {
    "iphone-timer": (SIM_IPHONE, ()),
    "ipad-timer": (SIM_IPAD, ("-PadTab", "timer")),
    "ipad-calendar": (SIM_IPAD, ("-PadTab", "calendar")),
    "ipad-reports": (SIM_IPAD, ("-PadTab", "reports")),
}


def capture_simulators(names, raw):
    subprocess.run(["make", "--no-print-directory", "sim", "ARGS=-UITesting YES"], cwd=ROOT, check=True)
    devices = {name: simulator(name) for name in (SIM_IPHONE, SIM_IPAD)}
    for udid in devices.values():
        prepare_simulator(udid)
    rotate_to_landscape(devices[SIM_IPAD])
    try:
        for name in names:
            print(name, flush=True)
            device, arguments = IOS_SHOTS[name]
            launch_on_simulator(devices[device], *arguments)
            simctl("io", devices[device], "screenshot", str(raw / f"{name}.png"))
    finally:
        for udid in devices.values():
            simctl("status_bar", udid, "clear")
            simctl("terminate", udid, debug_app_id())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("raw", type=Path, help="the folder for the raw images")
    parser.add_argument("names", nargs="*", help="the shots to take; default all")
    args = parser.parse_args()
    known = [*MAC_SHOTS, *IOS_SHOTS]
    names = args.names or known
    if unknown := sorted(set(names) - set(known)):
        parser.error(f"unknown shots {json.dumps(unknown)}; known: {', '.join(known)}")
    args.raw.mkdir(parents=True, exist_ok=True)
    try:
        if mac := [name for name in names if name in MAC_SHOTS]:
            capture_mac(mac, args.raw)
        if ios := [name for name in names if name in IOS_SHOTS]:
            capture_simulators(ios, args.raw)
    except app.DriverError as error:
        print(f"capture_screenshots: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
