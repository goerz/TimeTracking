#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "pyobjc-framework-ApplicationServices",
#     "pyobjc-framework-Quartz",
# ]
# ///
"""Drive the Debug Mac app through the Accessibility API and real input events.

The stand-in for an XCUITest when macOS can't enable Automation Mode. It runs
only against the Debug app launched with `-UITesting YES`, so the store is in
memory, and refuses to send input unless that app is frontmost, so nothing
lands in another app. The Mac's keyboard and pointer must be free while it runs.

    scripts/drive_mac_app.py launch --fixture small --calendar
    scripts/drive_mac_app.py tree --filter calendar.
    scripts/drive_mac_app.py click calendar.entry --label "Clarify intro" --mods cmd
    scripts/drive_mac_app.py drag calendar.entry --label "Plan" --by 0,72
    scripts/drive_mac_app.py key j --mods cmd
    scripts/drive_mac_app.py shot /path/to/file.png
    scripts/drive_mac_app.py quit

A target is an accessibility identifier, optionally narrowed by `--label`, or
the screen point `x,y`. The pointer goes to the element's center, or to `--at
fx,fy` (fractions of its frame), plus `--offset dx,dy` in points. `launch` goes
through `make mac-debug`, which builds and takes the runtime lock, and fixes the
clock at the UI tests' 2024-03-14T10:00:00.

Import it for longer scenarios: `find`, `click`, `drag`, and the rest are plain
functions. See `--help` of each command for the details.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import ApplicationServices as AX
import Quartz

ROOT = Path(__file__).resolve().parent.parent
FIXED_NOW = "2024-03-14T10:00:00"
AUTH_OWNERS = {"coreautha", "SecurityAgent"}

MODIFIERS = {
    # name: (virtual key code, event flag)
    "cmd": (55, Quartz.kCGEventFlagMaskCommand),
    "shift": (56, Quartz.kCGEventFlagMaskShift),
    "opt": (58, Quartz.kCGEventFlagMaskAlternate),
    "ctrl": (59, Quartz.kCGEventFlagMaskControl),
}
KEYS = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
    "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
    "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
}  # fmt: skip


class DriverError(Exception):
    pass


# MARK: The app


def local_setting(name):
    """A value from local.mk, which holds the personal identifiers."""
    text = (ROOT / "local.mk").read_text()
    match = re.search(rf"^{name}\s*\??=\s*(\S+)", text, re.MULTILINE)
    if not match:
        raise DriverError(f"{name} is not set in local.mk")
    return match.group(1)


def debug_bundle_id():
    return local_setting("BUNDLE_ID") + ".debug"


def launch_services_pid(specifier):
    """The pid of the app `lsappinfo` knows by `specifier`, or None. Launch
    Services stays current in a long-lived process, as NSRunningApplication
    and NSWorkspace don't without a run loop."""
    found = subprocess.run(["lsappinfo", *specifier], capture_output=True, text=True).stdout.strip()
    if not found:
        return None
    info = subprocess.run(["lsappinfo", "info", "-only", "pid", found], capture_output=True, text=True).stdout
    match = re.search(r"pid\D*(\d+)", info)
    return int(match.group(1)) if match else None


def running_pid():
    """The pid of the running Debug app, or None."""
    return launch_services_pid(["find", f"bundleid={debug_bundle_id()}"])


def checked_pid():
    """The Debug app's pid, after checking that it runs on the in-memory store."""
    pid = running_pid()
    if pid is None:
        raise DriverError("the Debug app is not running")
    command = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True).stdout
    if "-UITesting YES" not in command:
        raise DriverError("the running Debug app has no -UITesting YES, so it uses a real store")
    return pid


def launch(fixture="small", calendar=False, reset=True, extra=(), wait=60):
    """Builds and opens the Debug app as the UI tests launch it."""
    args = ["-UITesting", "YES", "-Fixture", fixture]
    args += ["-ResetState", "YES"] if reset else []
    args += ["-CalendarAccess", "YES"] if calendar else []
    args += list(extra)
    environment = dict(os.environ, TIMETRACKING_NOW=FIXED_NOW)
    subprocess.run(["make", "mac-debug", f"ARGS={' '.join(args)}"], cwd=ROOT, env=environment, check=True)
    deadline = time.time() + wait
    while time.time() < deadline:
        if running_pid() is not None and windows():
            answer_onboarding()
            clear_auth_prompts()
            return
        time.sleep(0.2)
    raise DriverError("the Debug app opened no window")


def answer_onboarding():
    """Answers the first-launch alert with Later, as `launchPastOnboarding` does."""
    deadline = time.time() + 5
    while time.time() < deadline:
        for element in walk():
            if element.identifier == "onboarding.later":
                AX.AXUIElementPerformAction(element.ref, "AXPress")
                return
        time.sleep(0.2)


def quit_app():
    from AppKit import NSRunningApplication

    if running_pid() is not None:
        for element in walk():
            if element.identifier == "onboarding.later":
                AX.AXUIElementPerformAction(element.ref, "AXPress")
    for app in NSRunningApplication.runningApplicationsWithBundleIdentifier_(debug_bundle_id()):
        app.terminate()
    deadline = time.time() + 10
    while time.time() < deadline and running_pid() is not None:
        time.sleep(0.1)
    if running_pid() is not None:
        raise DriverError("the Debug app did not quit (an open sheet or alert?)")


def app_element():
    return AX.AXUIElementCreateApplication(checked_pid())


def activate():
    """Brings the Debug app to the front and confirms it is there."""
    pid = checked_pid()
    element = AX.AXUIElementCreateApplication(pid)
    for _ in range(50):
        if frontmost_pid() == pid:
            return
        AX.AXUIElementSetAttributeValue(element, "AXFrontmost", True)
        time.sleep(0.1)
    raise DriverError(f"the Debug app is not frontmost (pid {frontmost_pid()} is), so no input goes out")


def frontmost_pid():
    """The frontmost app's pid (the system-wide AX element fails while a
    system prompt is up)."""
    return launch_services_pid(["front"])


def auth_windows():
    """The frames of system authentication prompts on screen, as (x, y, width, height)."""
    info = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
    frames = []
    for item in info:
        if item.get("kCGWindowOwnerName") in AUTH_OWNERS:
            bounds = item["kCGWindowBounds"]
            frames.append((bounds["X"], bounds["Y"], bounds["Width"], bounds["Height"]))
    return frames


def refuse_auth_prompt(*points):
    """Stops before the pointer can touch an authentication prompt. Such a
    prompt is the owner's to answer; the driver never clicks, types into, or
    dismisses one."""
    for x, y, width, height in auth_windows():
        for point in points:
            if x - 4 <= point[0] <= x + width + 4 and y - 4 <= point[1] <= y + height + 4:
                raise DriverError(f"{point} lies on an authentication prompt, which is the owner's to answer")


def refuse_keys_outside_app():
    """Stops before a key can reach an authentication prompt: with one on
    screen, keys go out only while the Debug app is active and has a key window."""
    if not auth_windows():
        return
    pid = checked_pid()
    keyed = attribute(AX.AXUIElementCreateApplication(pid), "AXFocusedWindow")
    if frontmost_pid() != pid or keyed is None:
        raise DriverError("an authentication prompt is up and the Debug app has no key window, so no keys go out")


# MARK: Accessibility


@dataclass
class Element:
    ref: object
    role: str
    identifier: str
    label: str
    value: object
    frame: tuple  # x, y, width, height
    depth: int = 0

    @property
    def center(self):
        return self.point(0.5, 0.5)

    def point(self, fx, fy, dx=0, dy=0):
        x, y, width, height = self.frame
        return (x + fx * width + dx, y + fy * height + dy)

    def line(self):
        x, y, width, height = self.frame
        value = "" if self.value is None else f" value={str(self.value)!r}"
        name = f" id={self.identifier}" if self.identifier else ""
        label = f" label={self.label!r}" if self.label else ""
        return f"{'  ' * self.depth}{self.role}{name}{label}{value} [{x:.0f},{y:.0f} {width:.0f}x{height:.0f}]"

    def to_json(self):
        return {
            "role": self.role,
            "identifier": self.identifier,
            "label": self.label,
            "value": None if self.value is None else str(self.value),
            "frame": list(self.frame),
        }


def attribute(ref, name):
    error, value = AX.AXUIElementCopyAttributeValue(ref, name, None)
    return value if error == 0 else None


def geometry(value, kind):
    if value is None:
        return None
    ok, result = AX.AXValueGetValue(value, kind, None)
    return result if ok else None


def wrap(ref, depth=0):
    position = geometry(attribute(ref, "AXPosition"), AX.kAXValueCGPointType)
    size = geometry(attribute(ref, "AXSize"), AX.kAXValueCGSizeType)
    label = attribute(ref, "AXTitle") or attribute(ref, "AXDescription") or ""
    value = attribute(ref, "AXValue")
    if value is not None and not isinstance(value, (str, int, float, bool)):
        value = str(value)
    return Element(
        ref=ref,
        role=str(attribute(ref, "AXRole") or ""),
        identifier=str(attribute(ref, "AXIdentifier") or ""),
        label=str(label),
        value=value,
        frame=(position.x, position.y, size.width, size.height) if position and size else (0, 0, 0, 0),
        depth=depth,
    )


def walk(root=None, depth=0, max_depth=60, menus=False):
    """Every element under `root`, depth first; the menu bar only with `menus`."""
    root = root if root is not None else app_element()
    for child in attribute(root, "AXChildren") or []:
        element = wrap(child, depth)
        if element.role == "AXMenuBar" and not menus:
            continue
        yield element
        if depth < max_depth:
            yield from walk(child, depth + 1, max_depth, menus)


def windows():
    return [wrap(window) for window in attribute(app_element(), "AXWindows") or []]


def all_matching(identifier, label=None, menus=False):
    return [
        element
        for element in walk(menus=menus)
        if element.identifier == identifier and (label is None or element.label == label)
    ]


def find(identifier, label=None, timeout=5, menus=False):
    """The first element with `identifier` (and `label`), waiting for it."""
    deadline = time.time() + timeout
    while True:
        matches = all_matching(identifier, label, menus)
        if matches:
            return matches[0]
        if time.time() >= deadline:
            raise DriverError(f"no element {identifier!r}" + (f" labeled {label!r}" if label else ""))
        time.sleep(0.2)


def exists(identifier, label=None):
    return bool(all_matching(identifier, label))


def focused():
    """The app's focused element, or None."""
    ref = attribute(app_element(), "AXFocusedUIElement")
    return wrap(ref) if ref is not None else None


def move_window(x, y, index=0):
    """Moves a window by the Accessibility API, for example out from under a system prompt."""
    point = AX.AXValueCreate(AX.kAXValueCGPointType, Quartz.CGPointMake(x, y))
    AX.AXUIElementSetAttributeValue(windows()[index].ref, "AXPosition", point)


def clear_auth_prompts():
    """Moves the main window below any authentication prompt, which stays as it is."""
    frames = auth_windows()
    if frames:
        x, _, _, _ = windows()[0].frame
        move_window(x, max(y + height for _, y, _, height in frames) + 20)


def press_menu(*path):
    """Chooses a menu item by its titles, as `press_menu("Window", "Mini Timer")`."""
    activate()
    node = attribute(app_element(), "AXMenuBar")
    for title in path:
        children = attribute(node, "AXChildren") or []
        if len(children) == 1 and attribute(children[0], "AXRole") == "AXMenu":
            children = attribute(children[0], "AXChildren") or []
        match = [child for child in children if attribute(child, "AXTitle") == title]
        if not match:
            raise DriverError(f"no menu item {title!r}")
        node = match[0]
    AX.AXUIElementPerformAction(node, "AXPress")


# MARK: Input


def source():
    return Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)


def post(event):
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def flags(mods):
    value = 0
    for name in mods:
        value |= MODIFIERS[name][1]
    return value


def hold_modifiers(mods, down):
    current = 0
    for name in mods if down else reversed(mods):
        code, flag = MODIFIERS[name]
        current = current | flag if down else current & ~flag
        event = Quartz.CGEventCreateKeyboardEvent(source(), code, down)
        Quartz.CGEventSetFlags(event, flags(mods) if down else current)
        post(event)
        time.sleep(0.02)


def mouse(kind, point, mods=(), button=Quartz.kCGMouseButtonLeft, clicks=1):
    event = Quartz.CGEventCreateMouseEvent(source(), kind, point, button)
    Quartz.CGEventSetFlags(event, flags(mods))
    Quartz.CGEventSetIntegerValueField(event, Quartz.kCGMouseEventClickState, clicks)
    post(event)


def hover(point, settle=0.3):
    activate()
    start = pointer()
    refuse_auth_prompt(point)
    for step in range(1, 9):
        fraction = step / 8
        mouse(
            Quartz.kCGEventMouseMoved,
            (start[0] + (point[0] - start[0]) * fraction, start[1] + (point[1] - start[1]) * fraction),
        )
        time.sleep(0.01)
    time.sleep(settle)


def pointer():
    location = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
    return (location.x, location.y)


def click(point, mods=(), count=1, right=False, linger=0.05):
    """Clicks at `point`; `count` 2 is a double click. The modifiers stay down
    for `linger` seconds after the button comes up."""
    hover(point, settle=0.1)
    down, up, button = (
        (Quartz.kCGEventRightMouseDown, Quartz.kCGEventRightMouseUp, Quartz.kCGMouseButtonRight)
        if right
        else (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp, Quartz.kCGMouseButtonLeft)
    )
    hold_modifiers(mods, True)
    for number in range(1, count + 1):
        mouse(down, point, mods, button, number)
        time.sleep(0.03)
        mouse(up, point, mods, button, number)
        time.sleep(0.05)
    time.sleep(max(0, linger - 0.05))
    hold_modifiers(mods, False)
    time.sleep(0.2)


def drag(start, end, mods=(), hold=0.1, steps=20, pause=0.0):
    """Presses at `start`, holds, moves to `end` in steps, and releases."""
    refuse_auth_prompt(start, end, ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2))
    hover(start, settle=0.1)
    hold_modifiers(mods, True)
    mouse(Quartz.kCGEventLeftMouseDown, start, mods)
    time.sleep(hold)
    for step in range(1, steps + 1):
        fraction = step / steps
        point = (start[0] + (end[0] - start[0]) * fraction, start[1] + (end[1] - start[1]) * fraction)
        mouse(Quartz.kCGEventLeftMouseDragged, point, mods)
        time.sleep(0.015)
    time.sleep(pause)
    mouse(Quartz.kCGEventLeftMouseUp, end, mods)
    hold_modifiers(mods, False)
    time.sleep(0.3)


def scroll(point, dy, dx=0):
    hover(point, settle=0.05)
    event = Quartz.CGEventCreateScrollWheelEvent(source(), Quartz.kCGScrollEventUnitPixel, 2, int(dy), int(dx))
    post(event)
    time.sleep(0.3)


def key(name, mods=()):
    activate()
    refuse_keys_outside_app()
    code = KEYS[name]
    hold_modifiers(mods, True)
    for down in (True, False):
        event = Quartz.CGEventCreateKeyboardEvent(source(), code, down)
        Quartz.CGEventSetFlags(event, flags(mods))
        post(event)
        time.sleep(0.02)
    hold_modifiers(mods, False)
    time.sleep(0.2)


def type_text(text):
    activate()
    refuse_keys_outside_app()
    for character in text:
        for down in (True, False):
            event = Quartz.CGEventCreateKeyboardEvent(source(), 0, down)
            Quartz.CGEventKeyboardSetUnicodeString(event, len(character), character)
            post(event)
        time.sleep(0.02)
    time.sleep(0.2)


# MARK: Screenshots


def window_ids():
    """The app's on-screen windows, front to back, as (window id, title, bounds)."""
    pid = checked_pid()
    info = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
    return [
        (int(item["kCGWindowNumber"]), str(item.get("kCGWindowName", "")), dict(item["kCGWindowBounds"]))
        for item in info
        if item["kCGWindowOwnerPID"] == pid and item["kCGWindowLayer"] == 0
    ]


def screenshot(path, window=None):
    """Writes the frontmost (or the given) window to `path`, without its shadow."""
    window = window if window is not None else window_ids()[0][0]
    subprocess.run(["screencapture", "-x", "-o", "-l", str(window), str(path)], check=True)


# MARK: Command line


def pair(text):
    first, second = text.split(",")
    return (float(first), float(second))


def resolve(target, args):
    """The screen point of a target, from the command's `--label`, `--at`, and `--offset`."""
    if re.fullmatch(r"-?[\d.]+,-?[\d.]+", target):
        base = pair(target)
        offset = pair(args.offset)
        return (base[0] + offset[0], base[1] + offset[1])
    element = find(target, args.label)
    fx, fy = pair(args.at)
    dx, dy = pair(args.offset)
    return element.point(fx, fy, dx, dy)


def mods_of(args):
    return [name for name in args.mods.split(",") if name]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    def add(name, help_text, target=False):
        command = commands.add_parser(name, help=help_text, description=help_text)
        if target:
            command.add_argument("target", help="accessibility identifier, or the screen point x,y")
            command.add_argument("--label", help="narrow the identifier to this label")
            command.add_argument("--at", default="0.5,0.5", help="fractions of the frame, fx,fy")
            command.add_argument("--offset", default="0,0", help="points added to the position, dx,dy")
        return command

    command = add("launch", "Build with make mac-debug and open the Debug app")
    command.add_argument("--fixture", default="small", help="small, large, or running")
    command.add_argument("--calendar", action="store_true", help="add -CalendarAccess YES")
    command.add_argument("--keep-state", action="store_true", help="leave out -ResetState YES")
    command.add_argument("--extra", default="", help="further launch arguments, space separated")
    add("quit", "Quit the Debug app")
    add("status", "Show the pid, the frontmost pid, the focused element, and the windows")
    command = add("tree", "Print the accessibility tree")
    command.add_argument("--filter", help="only lines containing this text")
    command.add_argument("--menus", action="store_true", help="include the menu bar")
    command = add("find", "Print the elements with an identifier as JSON")
    command.add_argument("identifier")
    command.add_argument("--label")
    command = add("click", "Click a target", target=True)
    command.add_argument("--mods", default="", help="comma separated: cmd, shift, opt, ctrl")
    command.add_argument("--count", type=int, default=1, help="2 for a double click")
    command.add_argument("--right", action="store_true", help="the secondary button")
    add("hover", "Move the pointer to a target", target=True)
    command = add("drag", "Drag from a target", target=True)
    command.add_argument("--by", help="the distance dx,dy")
    command.add_argument("--to", help="the end: an identifier or x,y")
    command.add_argument("--to-label", help="narrow --to to this label")
    command.add_argument("--mods", default="", help="comma separated: cmd, shift, opt, ctrl")
    command.add_argument("--hold", type=float, default=0.1, help="seconds before moving")
    command = add("scroll", "Scroll at a target", target=True)
    command.add_argument("--dy", type=float, default=-100)
    command.add_argument("--dx", type=float, default=0)
    command = add("key", "Press a key, for example j, return, space, left, or escape")
    command.add_argument("name")
    command.add_argument("--mods", default="", help="comma separated: cmd, shift, opt, ctrl")
    command = add("type", "Type text into the focused element")
    command.add_argument("text")
    command = add("menu", "Choose a menu item by its titles")
    command.add_argument("path", nargs="+")
    command = add("move", "Move the main window to the screen point x,y")
    command.add_argument("point")
    command = add("shot", "Write a window screenshot with screencapture -l")
    command.add_argument("path")
    command.add_argument("--window", type=int, help="the window id; default the frontmost window")

    args = parser.parse_args()
    try:
        run(args)
    except DriverError as error:
        print(f"drive_mac_app: {error}", file=sys.stderr)
        sys.exit(1)


def run(args):
    match args.command:
        case "launch":
            launch(args.fixture, args.calendar, not args.keep_state, args.extra.split())
        case "quit":
            quit_app()
        case "status":
            pid = checked_pid()
            print(f"pid {pid}, frontmost {frontmost_pid()}")
            element = focused()
            print("focused:", element.line() if element else None)
            for number, title, bounds in window_ids():
                print(f"window {number} {title!r} {bounds}")
            print("authentication prompts:", auth_windows())
        case "tree":
            for element in walk(menus=args.menus):
                line = element.line()
                if args.filter is None or args.filter in line:
                    print(line)
        case "find":
            print(json.dumps([e.to_json() for e in all_matching(args.identifier, args.label)], indent=2))
        case "click":
            click(resolve(args.target, args), mods_of(args), args.count, args.right)
        case "hover":
            hover(resolve(args.target, args))
        case "drag":
            start = resolve(args.target, args)
            if args.by:
                by = pair(args.by)
                end = (start[0] + by[0], start[1] + by[1])
            elif args.to and re.fullmatch(r"-?[\d.]+,-?[\d.]+", args.to):
                end = pair(args.to)
            elif args.to:
                end = find(args.to, args.to_label).center
            else:
                raise DriverError("drag needs --by or --to")
            drag(start, end, mods_of(args), args.hold)
        case "scroll":
            scroll(resolve(args.target, args), args.dy, args.dx)
        case "key":
            key(args.name, mods_of(args))
        case "type":
            type_text(args.text)
        case "menu":
            press_menu(*args.path)
        case "move":
            move_window(*pair(args.point))
        case "shot":
            screenshot(args.path, args.window)


if __name__ == "__main__":
    main()
