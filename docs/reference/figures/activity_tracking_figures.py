#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///
"""Draws the SVG figures of activity_tracking.md into this folder.

    docs/reference/figures/activity_tracking_figures.py

The spec inlines the SVGs (`{raw} html` with `:file:`), so links inside a
figure jump to the spec's sections and the colors follow Furo's light or dark
theme through the `--tt-*` properties of docs/_static/figures.css. Every color
has a light fallback, so a file opened on its own still reads. Coordinates are
in a 760-unit-wide viewBox, the width of Furo's content column.
"""

import html
import math
from pathlib import Path

HERE = Path(__file__).parent
e = html.escape

# Shared styles, scoped to one figure's id so that inlined figures don't
# affect each other or the page.
STYLE = """
#{id} {{ width: 100%; height: auto; display: block; margin: 0 auto; max-width: 760px; }}
#{id} text {{ font-family: var(--font-stack, -apple-system, sans-serif); font-size: 12px; fill: var(--tt-fg, #1c2529); }}
#{id} .note {{ fill: var(--tt-muted, #5c6b72); }}
#{id} .rel {{ fill: var(--tt-fg, #1c2529); }}
#{id} .zlabel {{ font-weight: 600; fill: var(--tt-muted, #5c6b72); }}
#{id} .lname {{ font-size: 14px; font-weight: 600; }}
#{id} .cname {{ font-size: 14px; font-weight: 600; }}
#{id} .cname.sm {{ font-size: 12px; }}
#{id} .sname {{ font-family: var(--font-stack--monospace, ui-monospace, monospace); font-size: 13px; font-weight: 600; }}
#{id} .mono {{ font-family: var(--font-stack--monospace, ui-monospace, monospace); }}
#{id} .link {{ fill: var(--tt-accent, #0b6e75); text-decoration: underline; }}
#{id} .wake {{ fill: var(--tt-accent, #0b6e75); }}
#{id} .ptext {{ font-size: 13px; font-weight: 600; fill: var(--tt-warn, #a4560a); }}
#{id} .ptext.planned {{ fill: var(--tt-muted, #5c6b72); font-weight: 500; }}
#{id} .pill {{ fill: var(--tt-warn-soft, #fbeedd); stroke: var(--tt-warn, #a4560a); stroke-width: 1.3; }}
#{id} .pill.planned {{ fill: none; stroke: var(--tt-muted, #5c6b72); stroke-dasharray: 4 3; }}
#{id} .box {{ fill: var(--tt-panel, #ffffff); stroke: var(--tt-line, #b6c2c8); stroke-width: 1.2; }}
#{id} .box.dev {{ stroke: var(--tt-fg, #1c2529); stroke-width: 1.4; }}
#{id} .store {{ fill: var(--tt-local, #eeeff3); stroke: var(--tt-line, #b6c2c8); stroke-width: 1.2; }}
#{id} .frame {{ fill: none; stroke: var(--tt-line, #b6c2c8); stroke-width: 1.2; stroke-dasharray: 6 4; }}
#{id} .rule {{ stroke: var(--tt-line, #b6c2c8); }}
#{id} .lead {{ fill: none; stroke: var(--tt-fg, #1c2529); stroke-width: 1.1; }}
#{id} path.wl, #{id} line.wl {{ fill: none; stroke: var(--tt-accent, #0b6e75); stroke-width: 1.2; stroke-dasharray: 5 4; }}
#{id} .loop {{ fill: none; stroke: var(--tt-warn, #a4560a); stroke-width: 2; }}
#{id} .ahead {{ fill: var(--tt-fg, #1c2529); }}
#{id} .lhead {{ fill: var(--tt-warn, #a4560a); }}
#{id} .whead {{ fill: var(--tt-accent, #0b6e75); }}
#{id} .soft {{ fill: var(--tt-accent-soft, #e0eff0); stroke: var(--tt-accent, #0b6e75); stroke-width: 1; }}
#{id} .hot {{ fill: var(--tt-accent, #0b6e75); }}
#{id} .hot-text {{ fill: var(--tt-panel, #ffffff); }}
#{id} .bgblock {{ fill: none; stroke: var(--tt-accent, #0b6e75); stroke-width: 1; stroke-dasharray: 4 3; }}
#{id} .bar-bg {{ fill: var(--tt-rule, #dde3e6); }}
#{id} .bar {{ fill: var(--tt-accent, #0b6e75); }}
#{id} .pop {{ fill: var(--tt-panel, #ffffff); stroke: var(--tt-line, #b6c2c8); stroke-width: 1; }}
#{id} .devtext {{ font-weight: 600; fill: var(--tt-warn, #a4560a); }}
#{id} .b {{ font-weight: 600; }}
#{id} .head {{ font-size: 15px; font-weight: 600; }}
#{id} .small {{ font-size: 11px; }}
"""


class Svg:
    def __init__(self, fid, w, h, label):
        self.fid = fid
        self.parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" id="{fid}" viewBox="0 0 {w} {h}" role="img" aria-label="{e(label)}">',
            "<style>" + STYLE.format(id=fid) + "</style>",
            "<defs>"
            f'<marker id="{fid}-ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path class="ahead" d="M0 0 L10 5 L0 10 z"/></marker>'
            f'<marker id="{fid}-lh" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path class="lhead" d="M0 0 L10 5 L0 10 z"/></marker>'
            f'<marker id="{fid}-wh" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path class="whead" d="M0 0 L10 5 L0 10 z"/></marker>'
            "</defs>",
        ]

    def add(self, s):
        self.parts.append(s)

    def comment(self, s):
        self.parts.append(f"<!-- {s} -->")

    def m(self, kind):
        return f"url(#{self.fid}-{kind})"

    def label(self, x, y, text, anchor="start", cls="rel"):
        self.add(f'<text class="{cls}" x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}">{e(text)}</text>')

    def link(self, x, y, text, href, anchor="middle"):
        self.add(f'<a href="#{href}"><text class="link" x="{x}" y="{y}" text-anchor="{anchor}">{e(text)}</text></a>')

    def pill(self, cx, cy, w, text, planned=False):
        cls = " planned" if planned else ""
        self.add(f'<rect class="pill{cls}" x="{cx - w / 2}" y="{cy - 15}" width="{w}" height="30" rx="15"/>')
        self.add(f'<text class="ptext{cls}" x="{cx}" y="{cy + 4.5}" text-anchor="middle">{e(text)}</text>')

    def ibox(self, x, y, w, h, title, lines):
        self.add(f'<rect class="box" x="{x}" y="{y}" width="{w}" height="{h}" rx="3"/>')
        self.label(x + w / 2, y + 19, title, "middle", "cname sm")
        for i, t in enumerate(lines):
            self.label(x + w / 2, y + 35 + 15 * i, t, "middle", "note")

    def obox(self, x, y, w, name, anchor, note, h=52):
        self.add(f'<rect class="box" x="{x}" y="{y}" width="{w}" height="{h}" rx="3"/>')
        self.add(f'<a href="#{anchor}"><text class="cname link" x="{x + w / 2}" y="{y + 22}" text-anchor="middle">{e(name)}</text></a>')
        self.label(x + w / 2, y + 41, note, "middle", "note")

    def arc(self, cx, cy, r, a0, a1, ccw=False):
        def p(a):
            return cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))

        if ccw:
            (x0, y0), (x1, y1) = p(a1), p(a0)
            sweep, large = 0, 0
        else:
            (x0, y0), (x1, y1) = p(a0), p(a1)
            sweep, large = 1, 1 if (a1 - a0) % 360 > 180 else 0
        self.add(f'<path class="loop" d="M{x0:.1f} {y0:.1f} A{r} {r} 0 {large} {sweep} {x1:.1f} {y1:.1f}" marker-end="{self.m("lh")}"/>')

    def ring(self, cx, cy, r, spec, ccw=False):
        """Pills at angles on a circle, joined by arrowed arcs (clockwise
        unless ccw). Each entry of spec is (angle, width, text, planned)."""
        pills = []
        for ang, w, text, planned in spec:
            px = round(cx + r * math.cos(math.radians(ang)))
            py = round(cy + r * math.sin(math.radians(ang)))
            pills.append((px, py, w, text, planned))

        def blocked(a):
            x = cx + r * math.cos(math.radians(a))
            y = cy + r * math.sin(math.radians(a))
            return any(abs(x - px) <= w / 2 + 5 and abs(y - py) <= 20 for px, py, w, _, _ in pills)

        step = 0.5
        angles = [i * step for i in range(int(360 / step))]
        start = next(a for a in angles if blocked(a))
        run = last = None
        for a in [(start + a) % 360 for a in angles] + [start]:
            if not blocked(a):
                if run is None:
                    run = a
                last = a
            elif run is not None:
                a0, a1 = run, last if last >= run else last + 360
                if a1 - a0 > 6:
                    if ccw:
                        self.arc(cx, cy, r, a0 + 2, a1, ccw=True)
                    else:
                        self.arc(cx, cy, r, a0, a1 - 2)
                run = None
        for px, py, w, text, planned in pills:
            self.pill(px, py, w, text, planned)

    def write(self, name):
        self.add("</svg>")
        (HERE / name).write_text("\n".join(self.parts) + "\n")


def figure_loops():
    """Figure 1: the agent's loops around samples.sqlite."""
    s = Svg(
        "tt-fig-loops", 760, 1160,
        "The agent on the Mac runs a local activity loop, a remote activity loop, a request "
        "handler, and a rebuild loop around samples.sqlite. The iPhone and iPad upload "
        "DeviceEvents to CloudKit, and Safari syncs their visits into History.db. The rebuild "
        "loop writes the block log and current.json.",
    )
    FY1 = 1025
    s.comment("Frame: everything inside runs in the agent on the Mac")
    s.add(f'<rect class="frame" x="8" y="8" width="744" height="{FY1 - 8}" rx="8"/>')
    s.label(22, 30, "The Mac: the agent, one step at a time", "start", "zlabel")
    IX, IW = 54, 122

    s.comment("Local activity loop")
    LX, LY, LR = 370, 175, 90
    s.ring(LX, LY, LR, [(150, 140, "1  Take a Sample", False), (270, 200, "2  Build Samples for gaps", False), (30, 150, "3  Drop old Samples", False)])
    s.ibox(IX, 63, IW, 44, "knowledgeC.db", ["macOS app usage"])
    s.ibox(IX, 198, IW, 44, "macOS", ["apps, windows, input"])
    s.add(f'<line class="lead" x1="{IX + IW}" y1="85" x2="269" y2="85" marker-end="{s.m("ah")}"/>')
    s.add(f'<line class="lead" x1="{IX + IW}" y1="220" x2="221" y2="220" marker-end="{s.m("ah")}"/>')
    s.label(370, 56, "every 15 min, from app usage: time the agent didn't run", "middle", "note")
    s.label(334, 284, "every pass: one Sample;", "end", "note")
    s.label(334, 299, "presence to current.json", "end", "note")
    s.label(406, 284, "daily: > 90 days old", "start", "note")
    s.link(LX, 130, "details", "tracking-local")
    s.label(LX, 150, "Local activity loop", "middle", "lname")
    for i, t in enumerate(("every 30 s, and at once on a", "presence or app change or a", "tracker-event message")):
        s.label(LX, 167 + 15 * i, t, "middle", "note")

    s.comment("Remote activity loop")
    RX, RY, RR = 370, 455, 100
    s.ring(RX, RY, RR, [(210, 130, "1  Fetch events", False), (330, 160, "2  Events to Samples", False), (30, 150, "Host collectors", True), (150, 160, "3  Read synced Safari", False)])
    s.ibox(IX, 483, IW, 44, "History.db", ["Safari's visits"])
    s.add(f'<line class="lead" x1="{IX + IW}" y1="505" x2="202" y2="505" marker-end="{s.m("ah")}"/>')
    s.label(300, 375, "events added since the last fetch", "end", "note")
    s.label(440, 362, "redo each device-date", "start", "note")
    s.label(440, 377, "with new events", "start", "note")
    s.label(440, 572, "planned: Samples from", "start", "note")
    s.label(440, 587, "collectors on Linux hosts", "start", "note")
    s.label(300, 572, "visits of the last", "end", "note")
    s.label(300, 587, "24 h, again", "end", "note")
    s.link(RX, 432, "details", "tracking-remote")
    s.label(RX, 452, "Remote activity loop", "middle", "lname")
    s.label(RX, 470, "every 5 min", "middle", "note")

    s.comment("Request handler")
    QY = 640
    for i, t in enumerate(("Calendar: Delete This Activity…", "tracker-event forget-day,", "reapply-exclusions")):
        s.label(200, QY - 12 + 16 * i, t, "start", "wake")
    s.add(f'<line class="wl" x1="388" y1="{QY}" x2="419" y2="{QY}" marker-end="{s.m("wh")}"/>')
    s.pill(490, QY, 140, "Delete or re-filter")
    s.label(452, QY + 32, "a request, not a loop", "start", "note")
    s.link(452, QY + 47, "details", "tracking-requests", "start")

    s.comment("samples.sqlite")
    SX0, SX1, ST, SB = 590, 730, 60, 650
    scx = (SX0 + SX1) / 2
    s.add(f'<path class="store" d="M{SX0} {ST} V{SB} A{(SX1 - SX0) / 2} 12 0 0 0 {SX1} {SB} V{ST}"/>')
    s.add(f'<ellipse class="store" cx="{scx}" cy="{ST}" rx="{(SX1 - SX0) / 2}" ry="12"/>')
    s.label(scx, 100, "samples.sqlite", "middle", "sname")
    s.add(f'<line class="rule" x1="{SX0}" y1="118" x2="{SX1}" y2="118"/>')
    s.add(f'<a href="#tracking-records"><text class="cname link" x="{scx}" y="150" text-anchor="middle">Sample</text></a>')
    for i, t in enumerate(("and the", "DeviceEvents;", "kept 90 days")):
        s.label(scx, 168 + 15 * i, t, "middle", "note")
    s.add(f'<line class="rule" x1="{SX0}" y1="225" x2="{SX1}" y2="225"/>')
    s.label(scx, 255, "meta", "middle", "cname sm")
    for i, t in enumerate(("CloudKit token,", "app usage state,", "deleted ranges,", "changed dates,", "cutoff date,", "day ends, names")):
        if t.startswith("deleted"):
            s.link(scx, 273 + 15 * i, t, "tracking-records")
        else:
            s.label(scx, 273 + 15 * i, t, "middle", "note")
    s.label(scx, 380, "Samples are", "middle", "note")
    s.label(scx, 395, "written only by", "middle", "note")
    s.link(scx, 410, "insert and replace", "tracking-store")
    s.label(scx, 520, "every write", "middle", "note")
    s.label(scx, 535, "marks the dates", "middle", "note")
    s.label(scx, 550, "it changed", "middle", "note")

    s.comment("Loops and store")
    for y in (157, 455):
        s.add(f'<line class="lead" x1="{482 if y == 455 else 472}" y1="{y}" x2="{SX0 - 1}" y2="{y}" marker-start="{s.m("ah")}" marker-end="{s.m("ah")}"/>')
        s.label(SX0 - 8, y - 8, "writes", "end")
        s.label(SX0 - 8, y + 17, "reads", "end")
    s.add(f'<line class="lead" x1="561" y1="{QY}" x2="{SX0 - 1}" y2="{QY}" marker-end="{s.m("ah")}"/>')

    s.comment("Rebuild loop (counterclockwise)")
    BX, BY, BR = 530, 805, 90
    s.ring(BX, BY, BR, [(270, 170, "1  Read Samples of D", False), (180, 170, "2  Pick the foreground", False), (90, 120, "3  Form blocks", False), (0, 160, "4  Write blocks of D", False)], ccw=True)
    s.label(BX, 760, "Rebuild loop", "middle", "lname")
    s.label(BX, 852, "one changed date D", "middle", "note")
    s.link(BX, 868, "a pass, step by step", "tracking-rebuild")
    s.add(f'<line class="wl" x1="602" y1="657" x2="602" y2="699" marker-end="{s.m("wh")}"/>')
    s.add(f'<line class="lead" x1="614" y1="659" x2="614" y2="699" marker-start="{s.m("ah")}" marker-end="{s.m("ah")}"/>')
    s.label(626, 676, "wakes: dates changed", "start", "wake")
    s.label(626, 696, "reads Samples of D;", "start")
    s.label(626, 711, "updates the dates", "start")
    OY = 950
    s.add(f'<path class="lead" d="M640 821 V935 H490 V{OY - 1}" marker-end="{s.m("ah")}"/>')
    s.add(f'<path class="lead" d="M640 935 H660 V{OY - 1}" marker-end="{s.m("ah")}"/>')
    s.label(648, 860, "if changed", "start")
    s.obox(420, OY, 140, "block log", "tracking-format", "a file per date, iCloud")
    s.obox(590, OY, 140, "current.json", "tracking-current", "the open block")
    s.add(f'<path class="lead" d="M428 {QY + 15} V706 H300 V976 H419" marker-end="{s.m("ah")}"/>')
    s.label(308, 745, "frozen dates:", "start")
    s.label(308, 760, "edits the file", "start")

    s.comment("Outside the Mac: iPhone and iPad, CloudKit")
    s.add('<rect class="box dev" x="170" y="1045" width="390" height="105" rx="6"/>')
    s.label(182, 1066, "iPhone and iPad", "start", "cname")
    s.label(182, 1086, "Safari (Apple's) syncs its history via iCloud", "start", "note")
    s.add('<line class="rule" x1="182" y1="1097" x2="548" y2="1097"/>')
    s.label(182, 1117, "TimeTracking (ours): Screen Time, Focus, automations,", "start", "note")
    s.label(182, 1133, "Safari tabs, and its own time, uploaded as DeviceEvents", "start", "note")
    s.ibox(8, 1107, 142, 44, "CloudKit", ["DeviceEvent records"])
    s.add(f'<line class="lead" x1="170" y1="1129" x2="151" y2="1129" marker-end="{s.m("ah")}"/>')
    s.add(f'<path class="lead" d="M36 1107 V405 H217" marker-end="{s.m("ah")}"/>')
    s.label(44, 1000, "DeviceEvents", "start")
    s.add(f'<path class="lead" d="M186 1045 V580 H115 V528" marker-end="{s.m("ah")}"/>')
    s.label(192, 1016, "Safari's iCloud sync", "start")

    s.comment("Legend")
    lx = 590
    s.arc(lx + 8, 1066, 8, -60, 240)
    s.label(lx + 24, 1070, "a loop: steps in order", "start", "note")
    s.add(f'<line class="lead" x1="{lx}" y1="1092" x2="{lx + 20}" y2="1092" marker-end="{s.m("ah")}"/>')
    s.label(lx + 24, 1096, "data", "start", "note")
    s.add(f'<line class="wl" x1="{lx}" y1="1114" x2="{lx + 20}" y2="1114" marker-end="{s.m("wh")}"/>')
    s.label(lx + 24, 1118, "wakes a loop", "start", "note")
    s.add(f'<rect class="pill planned" x="{lx}" y="1132" width="20" height="12" rx="6"/>')
    s.label(lx + 24, 1142, "planned", "start", "note")
    s.write("activity_tracking_loops.svg")


def figure_summary():
    """Figure 3: the Calendar's activity column with the 09:52 block hovered,
    and the summary shown for it."""
    W, H = 760, 470
    s = Svg(
        "tt-fig-summary", W, H,
        "A Calendar activity column from 09:00 to 13:00 with four blocks, and the summary "
        "of the hovered 09:52 to 11:05 block: its workspaces MyApp, 2026_Noise, and Social "
        "with their shares and items, two background items, and a footer.",
    )

    s.comment("Activity column: 09:00 to 13:00")
    CX, CW, CT, CH = 70, 150, 24, 420

    def ty(h, m):
        return CT + (h * 60 + m - 540) / 240 * CH

    s.add(f'<line class="rule" x1="{CX}" y1="{CT}" x2="{CX}" y2="{CT + CH}"/>')
    for hh in (9, 10, 11, 12, 13):
        y = ty(hh, 0)
        s.add(f'<line class="rule" x1="{CX}" y1="{y:.1f}" x2="{CX + CW}" y2="{y:.1f}"/>')
        s.label(CX - 8, y + 4, f"{hh:02d}:00", "end", "note small")
    for (a, b, kind, text) in [
        ((9, 10), (9, 44), "soft", "2026_Noise"),
        ((9, 52), (11, 5), "hot", "MyApp"),
        ((11, 15), (11, 58), "bgblock", "background"),
        ((12, 15), (12, 55), "soft", "Mail"),
    ]:
        y0, y1 = ty(*a), ty(*b)
        s.add(f'<rect class="{kind}" x="{CX + 10}" y="{y0:.1f}" width="{CW - 20}" height="{y1 - y0:.1f}" rx="4"/>')
        s.label(CX + 17, y0 + 14, text, "start", "small hot-text" if kind == "hot" else "small")

    s.comment("Summary popover")
    PX, PY, PW = 270, 24, 470
    R = PX + PW - 16  # right edge of the text
    rows = []  # (y, svg) collected first, so the popover's height fits them
    y = PY + 26

    def line(text_left, text_right="", cls="", indent=0, right_cls="note"):
        nonlocal y
        out = [f'<text class="{cls}" x="{PX + 16 + indent}" y="{y}">{text_left}</text>']
        if text_right:
            out.append(f'<text class="{right_cls}" x="{R}" y="{y}" text-anchor="end">{e(text_right)}</text>')
        rows.append("".join(out))

    line('<tspan class="head">09:52 – 11:05</tspan>', "1 h 13 min")
    y += 20
    rows.append(f'<text class="note" x="{PX + 16}" y="{y}">Active 1 h 06 min · went idle · MacBook, <tspan class="devtext">iPhone</tspan></text>')

    def group(ws, path, mins, pct, items):
        nonlocal y
        y += 28
        rows.append(
            f'<text class="b" x="{PX + 16}" y="{y}">{e(ws)} <tspan class="note" font-weight="400">{e(path)}</tspan></text>'
            f'<text class="b" x="{R - 120}" y="{y}" text-anchor="end">{e(mins)}</text>'
            f'<rect class="bar-bg" x="{R - 110}" y="{y - 8}" width="70" height="6" rx="3"/>'
            f'<rect class="bar" x="{R - 110}" y="{y - 8}" width="{70 * pct / 100:.1f}" height="6" rx="3"/>'
            f'<text class="note small" x="{R}" y="{y}" text-anchor="end">{pct}%</text>'
        )
        for lab, t, dev in items:
            y += 19
            if dev:
                rows.append(f'<text x="{PX + 28}" y="{y}"><tspan class="devtext">{e(dev)}</tspan> {e(lab)}</text>'
                            f'<text class="note" x="{R}" y="{y}" text-anchor="end">{e(t)}</text>')
            else:
                line(e(lab), t, indent=12)

    group("MyApp", "~/Code/MyApp", "41 min", 62,
          [("WezTerm · refactor-parser", "24 min", ""), ("Safari · Fix parser #123", "11 min", ""), ("WezTerm · parser.swift", "6 min", "")])
    group("2026_Noise", "~/Papers/2026_Noise", "13 min", 20,
          [("Skim · notes.pdf", "9 min", ""), ("WezTerm · notes.tex", "4 min", "")])
    group("Social", "Screen Time set", "12 min", 18, [("Social", "12 min", "iPhone")])
    y += 16
    rows.append(f'<line class="rule" x1="{PX + 16}" y1="{y}" x2="{R}" y2="{y}"/>')
    y += 18
    line("Background", cls="b note small")
    y += 19
    rows.append(f'<text x="{PX + 16}" y="{y}">Claude Code · refactor-parser <tspan class="note">MyApp</tspan></text>'
                f'<text class="note" x="{R}" y="{y}" text-anchor="end">38 min</text>')
    y += 19
    rows.append(f'<text x="{PX + 16}" y="{y}">tmux · make test <tspan class="note">MyApp</tspan></text>'
                f'<text class="note" x="{R}" y="{y}" text-anchor="end">9 min</text>')
    y += 16
    rows.append(f'<line class="rule" x1="{PX + 16}" y1="{y}" x2="{R}" y2="{y}"/>')
    y += 18
    line("4 min rebuilt from app usage history · Click for every item", cls="note small")
    s.add(f'<rect class="pop" x="{PX}" y="{PY}" width="{PW}" height="{y + 14 - PY}" rx="10"/>')
    s.comment("Pointer from the hovered block to the popover")
    s.add(f'<line class="rule" x1="{CX + CW - 10}" y1="{ty(10, 20):.1f}" x2="{PX}" y2="{ty(10, 20):.1f}"/>')
    for r in rows:
        s.add(r)
    s.write("activity_tracking_summary.svg")


if __name__ == "__main__":
    figure_loops()
    figure_summary()
