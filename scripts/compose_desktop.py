"""Composes a clean Mac desktop around real windows (architecture.md §2.7).

A real full-screen capture would show the owner's own menu bar, Dock, and
wallpaper, so `scripts/capture_screenshots.py` hands the app's real windows,
status menu, and status item to `compose`, which places them on a desktop drawn
here. The wallpaper is drawn; the menu bar uses the system's fonts and SF
Symbols, and the Dock the system's icons of its standard apps. All sizes are
points on a 1512 x 982 screen, at 2x.

The desktop has the look of Reduce Transparency, on the Mac that takes these
images: a solid menu bar and Dock, which match its real windows and menu. The
menu bar takes its color from the status item's capture, which only works with
a solid bar.
"""

import os
from pathlib import Path

import AppKit
from Foundation import NSMakeRect, NSMakeSize, NSPoint
from PIL import Image, ImageDraw, ImageFilter

SCREEN = (1512, 982)
SCALE = 2
MENU_BAR_HEIGHT = 37
MARGIN = 22

DOCK_ICON = 58
DOCK_GAP = 7
DOCK_PADDING = 8
DOCK_BOTTOM = 6
DOCK_COLOR = (236, 236, 236, 255)
DOCK_RIM = (205, 205, 205, 255)
DOCK_APPS = [
    ("/System/Library/CoreServices/Finder.app", True),
    ("/Applications/Safari.app", True),
    ("/System/Applications/Mail.app", False),
    ("/System/Applications/Messages.app", False),
    ("/System/Applications/Notes.app", False),
    ("/System/Applications/Reminders.app", False),
    ("/System/Applications/Music.app", False),
    ("/System/Applications/System Settings.app", False),
]
TRASH_ICON = "/System/Library/CoreServices/Dock.app/Contents/Resources/trashempty@2x.png"

# Top right to bottom left of the drawn wallpaper, as soft patches of color.
WALLPAPER_BASE = ((34, 62, 122), (20, 34, 78))
WALLPAPER_PATCHES = [
    ((0.82, 0.10), 0.62, (86, 150, 214)),
    ((0.12, 0.28), 0.50, (70, 92, 186)),
    ((0.62, 0.86), 0.58, (122, 84, 176)),
    ((0.05, 0.95), 0.46, (28, 110, 150)),
]


def wallpaper():
    """Soft patches of color, drawn small and enlarged, so nothing has an edge."""
    size = (SCREEN[0] // 4, SCREEN[1] // 4)
    image = Image.linear_gradient("L").resize(size)
    image = Image.composite(
        Image.new("RGB", size, WALLPAPER_BASE[1]),
        Image.new("RGB", size, WALLPAPER_BASE[0]),
        image,
    )
    for (x, y), radius, color in WALLPAPER_PATCHES:
        mask = Image.new("L", size, 0)
        reach = radius * size[0] / 2
        center = (x * size[0], y * size[1])
        ImageDraw.Draw(mask).ellipse(
            (center[0] - reach, center[1] - reach, center[0] + reach, center[1] + reach), fill=200
        )
        mask = mask.filter(ImageFilter.GaussianBlur(reach * 0.55))
        image = Image.composite(Image.new("RGB", size, color), image, mask)
    pixels = (SCREEN[0] * SCALE, SCREEN[1] * SCALE)
    return image.resize(pixels, Image.Resampling.BICUBIC).convert("RGBA")


def visible_part(image):
    """Crops a capture to what shows; a menu's capture has a clear margin."""
    return image.crop(image.getchannel("A").point(lambda value: 255 if value > 8 else 0).getbbox())


def rounded_mask(size, radius):
    mask = Image.new("L", (size[0] * 4, size[1] * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] * 4 - 1, size[1] * 4 - 1), radius * 4, fill=255)
    return mask.resize(size, Image.Resampling.LANCZOS)


class Chrome:
    """A transparent layer in screen points, with y growing downward."""

    def __init__(self):
        width, height = SCREEN[0] * SCALE, SCREEN[1] * SCALE
        self.rep = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
            None, width, height, 8, 4, True, False, AppKit.NSCalibratedRGBColorSpace, 0, 0
        )
        self.rep.setSize_(NSMakeSize(*SCREEN))
        context = AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(self.rep)
        AppKit.NSGraphicsContext.setCurrentContext_(context)
        self.ink = AppKit.NSColor.blackColor().colorWithAlphaComponent_(0.86)

    def flipped(self, x, y, height):
        return x, SCREEN[1] - y - height

    def text(self, string, x, center_y, font, right=False):
        """Draws one line and returns its width."""
        attributes = {
            AppKit.NSFontAttributeName: font,
            AppKit.NSForegroundColorAttributeName: self.ink,
        }
        text = AppKit.NSAttributedString.alloc().initWithString_attributes_(string, attributes)
        size = text.size()
        left = x - size.width if right else x
        text.drawAtPoint_(NSPoint(*self.flipped(left, center_y - size.height / 2, size.height)))
        return size.width

    def symbol(self, name, right, center_y, points, weight=AppKit.NSFontWeightRegular):
        """Draws an SF Symbol ending at `right` and returns its width."""
        config = AppKit.NSImageSymbolConfiguration.configurationWithPointSize_weight_(points, weight)
        palette = AppKit.NSImageSymbolConfiguration.configurationWithPaletteColors_([self.ink])
        config = config.configurationByApplyingConfiguration_(palette)
        image = AppKit.NSImage.imageWithSystemSymbolName_accessibilityDescription_(name, None)
        if image is None:
            raise ValueError(f"no symbol {name}")
        image = image.imageWithSymbolConfiguration_(config)
        size = image.size()
        x, y = self.flipped(right - size.width, center_y - size.height / 2, size.height)
        image.drawInRect_(NSMakeRect(x, y, size.width, size.height))
        return size.width

    def icon(self, path, x, y, size):
        if path.endswith(".png"):
            image = AppKit.NSImage.alloc().initWithContentsOfFile_(path)
        else:
            # A link's icon would carry a shortcut arrow, and Safari is a link.
            image = AppKit.NSWorkspace.sharedWorkspace().iconForFile_(os.path.realpath(path))
        image.setSize_(NSMakeSize(size, size))
        left, bottom = self.flipped(x, y, size)
        image.drawInRect_(NSMakeRect(left, bottom, size, size))

    def dot(self, center_x, center_y):
        _, y = self.flipped(center_x, center_y, 0)
        self.ink.set()
        AppKit.NSBezierPath.bezierPathWithOvalInRect_(NSMakeRect(center_x - 2, y - 2, 4, 4)).fill()

    def line(self, x, top, bottom):
        AppKit.NSColor.blackColor().colorWithAlphaComponent_(0.18).set()
        AppKit.NSBezierPath.fillRect_(NSMakeRect(x, SCREEN[1] - bottom, 1, bottom - top))

    def image(self, scratch):
        AppKit.NSGraphicsContext.setCurrentContext_(None)
        data = self.rep.representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, {})
        data.writeToFile_atomically_(str(scratch), True)
        layer = Image.open(scratch).convert("RGBA")
        layer.load()
        scratch.unlink()
        return layer


def draw_menu_bar(chrome, menus, item_width, clock):
    """Draws the bar around a gap for the status item; returns the gap's left edge."""
    middle = MENU_BAR_HEIGHT / 2
    regular = AppKit.NSFont.menuBarFontOfSize_(13.5)
    bold = AppKit.NSFont.boldSystemFontOfSize_(13.5)
    x = 20
    x += chrome.text("\uf8ff", x, middle - 0.5, AppKit.NSFont.systemFontOfSize_(16)) + 20
    for index, title in enumerate(menus):
        x += chrome.text(title, x, middle, bold if index == 0 else regular) + 20

    right = SCREEN[0] - 16
    right -= chrome.text(clock, right, middle, regular, right=True) + 16
    for name, points in (
        ("switch.2", 13.5),
        ("magnifyingglass", 13.5),
        ("wifi", 14),
        ("battery.100percent", 15),
        ("speaker.wave.2.fill", 13),
    ):
        right -= chrome.symbol(name, right, middle, points) + 16
    return right - item_width + 6


def dock_layout(app_icon):
    """The Dock's icons with their left edges, and its frame in points."""
    apps = DOCK_APPS[:7] + [(app_icon, True)] + DOCK_APPS[7:]
    icons = []
    x = DOCK_PADDING
    for path, running in apps:
        icons.append((path, x, running))
        x += DOCK_ICON + DOCK_GAP
    separator = x + 1
    x += DOCK_GAP + 2
    icons.append((TRASH_ICON, x, False))
    width = x + DOCK_ICON + DOCK_PADDING
    height = DOCK_ICON + 2 * DOCK_PADDING
    left = (SCREEN[0] - width) // 2
    top = SCREEN[1] - DOCK_BOTTOM - height
    return icons, separator, (left, top, width, height)


def draw_dock(desktop, frame):
    """The Dock's solid background, with a thin rim and a soft shadow."""
    left, top, width, height = (value * SCALE for value in frame)
    radius = 25 * SCALE
    box = (left, top, left + width, top + height)
    mask = rounded_mask((width, height), radius)
    shadow = Image.new("RGBA", desktop.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), box, mask)
    desktop.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    panel = Image.new("RGBA", (width * 4, height * 4), (0, 0, 0, 0))
    ImageDraw.Draw(panel).rounded_rectangle(
        (0, 0, width * 4 - 1, height * 4 - 1), radius * 4, fill=DOCK_COLOR, outline=DOCK_RIM, width=8
    )
    desktop.alpha_composite(panel.resize((width, height), Image.Resampling.LANCZOS), (left, top))


def place_window(desktop, window, position):
    """Puts a window, by the top left of its image in points, with its shadow."""
    x, y = position[0] * SCALE, position[1] * SCALE
    alpha = window.getchannel("A")
    for blur, offset, opacity in ((44, 30, 0.42), (6, 3, 0.22)):
        mask = Image.new("L", desktop.size, 0)
        mask.paste(alpha.point(lambda value, o=opacity: round(value * o)), (x, y + offset))
        shadow = Image.new("RGBA", desktop.size, (0, 0, 0, 0))
        shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
        desktop.alpha_composite(shadow)
    desktop.alpha_composite(window, (x, y))


def compose(main_window, mini_timer, status_menu, status_item, app_icon, menus, clock, output):
    """Writes the desktop to `output`, from the captures' PNG files."""
    output = Path(output)
    main = Image.open(main_window).convert("RGBA")
    mini = Image.open(mini_timer).convert("RGBA")
    menu = visible_part(Image.open(status_menu).convert("RGBA"))
    item = Image.open(status_item).convert("RGBA")
    desktop = wallpaper()

    bar_color = item.getpixel((1, 1))
    ImageDraw.Draw(desktop).rectangle((0, 0, desktop.width, MENU_BAR_HEIGHT * SCALE - 1), fill=bar_color)
    icons, separator, frame = dock_layout(app_icon)
    draw_dock(desktop, frame)

    chrome = Chrome()
    item_left = draw_menu_bar(chrome, menus, item.width // SCALE, clock)
    left, top = frame[0], frame[1]
    for path, x, running in icons:
        chrome.icon(path, left + x, top + DOCK_PADDING, DOCK_ICON)
        if running:
            chrome.dot(left + x + DOCK_ICON / 2, top + DOCK_PADDING + DOCK_ICON + 4)
    chrome.line(left + separator, top + 12, top + frame[3] - 12)
    desktop.alpha_composite(chrome.image(output.with_suffix(".chrome.png")))
    item_top = (MENU_BAR_HEIGHT * SCALE - item.height) // 2
    desktop.alpha_composite(item, (round(item_left) * SCALE, item_top))

    place_window(desktop, main, (MARGIN, MENU_BAR_HEIGHT + 15))
    menu_top = MENU_BAR_HEIGHT + 2
    timer_top = menu_top + menu.height // SCALE + 14
    place_window(desktop, mini, (SCREEN[0] - MARGIN - mini.width // SCALE, timer_top))
    place_window(desktop, menu, (round(item_left), menu_top))
    desktop.convert("RGB").save(output)
