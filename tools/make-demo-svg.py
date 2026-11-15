"""Record a real byobu session (with byobu-keyhints installed) into an animated SVG.

    uv venv /tmp/demo-venv && uv pip install --python /tmp/demo-venv/bin/python pyte
    /tmp/demo-venv/bin/python tools/make-demo-svg.py docs/demo.svg

Needs byobu (tmux backend). Nothing here is part of the plugin; this only makes the
picture used in the README. The output is plain text (SVG), drawn as text and
rectangles, so it stays sharp at any size and passes the "every tracked file is text"
check in tests/audit.sh.

Everything runs in a sandbox. The environment is rebuilt from scratch (not inherited),
and HOME, BYOBU_CONFIG_DIR and TMUX_TMPDIR all point into a temporary directory, so your
own byobu sessions and config are never touched and no user or host name ends up in the
picture. byobu runs on a pty and its screen is replayed through pyte.
"""
import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time
from dataclasses import dataclass
from xml.sax.saxutils import escape

import pyte

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(REPO, "docs", "demo.svg")

COLS, ROWS = 140, 14  # wide enough for the longest hint (copy mode) plus the clock

# Geometry, in SVG user units (one unit is about one pixel at 100% zoom).
FONT_SIZE = 14
CELL_W, CELL_H = 8.4, 19
CAPTION_FONT_SIZE = 18
CAPTION_HEIGHT = 44
FONT_FAMILY = "'DejaVu Sans Mono','Menlo','Consolas','Liberation Mono',monospace"

DEFAULT_FG = "#cccccc"
DEFAULT_BG = "#181818"
CAPTION_BG = "#282834"
CAPTION_FG = "#ffdc8c"
CURSOR_OUTLINE = "#dcdcdc"

# xterm-ish palette for pyte's named colors
NAMED_COLORS = {
    "black": "#000000", "red": "#cd3131", "green": "#0dbc79",
    "brown": "#e5e510", "yellow": "#e5e510", "blue": "#2472c8",
    "magenta": "#bc3fbc", "cyan": "#11a8cd", "white": "#e5e5e5",
    "brightblack": "#666666", "brightred": "#f14c4c",
    "brightgreen": "#23d18b", "brightbrown": "#f5f543",
    "brightyellow": "#f5f543", "brightblue": "#3b8eea",
    "brightmagenta": "#d670d6", "brightcyan": "#29b8db",
    "brightwhite": "#ffffff",
}

# Keys as a terminal sends them (xterm-256color).
KEY_F5 = b"\x1b[15~"
KEY_CTRL_A = b"\x01"
KEY_CTRL_F2 = b"\x1b[1;5Q"
KEY_SHIFT_F2 = b"\x1b[1;2Q"
KEY_F7 = b"\x1b[18~"
KEY_SHIFT_F11 = b"\x1b[23;2~"
KEY_ALT_F9 = b"\x1b[20;3~"

# One entry per frame: (caption, keys to send first, seconds to show the result).
# The order follows the "When the hint changes" table in the README.
SCENARIO = [
    ("A single pane", b"", 2.2),
    ("Ctrl+F2  split left/right", KEY_CTRL_F2, 2.4),
    ("Shift+F2  split top/bottom", KEY_SHIFT_F2, 2.4),
    ("Ctrl+a  (the prefix key)", KEY_CTRL_A, 2.6),
    ("z  zoom the pane", b"z", 2.2),
    ("Shift+F11  unzoom", KEY_SHIFT_F11, 2.2),
    ("F7  copy mode", KEY_F7, 2.6),
    ("q  quit copy mode", b"q", 1.6),
    ("Alt+F9  type into ALL panes (easy to hit by accident)", KEY_ALT_F9, 2.8),
    ("Alt+F9  turn it off", KEY_ALT_F9, 1.8),
]


@dataclass(frozen=True)
class Style:
    fg: str
    bg: str
    bold: bool


@dataclass
class Frame:
    caption: str
    seconds: float
    rows: list  # ROWS lists of (character, Style)
    cursor: tuple  # (column, row), or None when hidden


def to_hex(name, default):
    """Turn a pyte color (a name, or a 6-digit hex string) into '#rrggbb'."""
    if name == "default":
        return default
    if name in NAMED_COLORS:
        return NAMED_COLORS[name]
    if len(name) == 6:
        try:
            int(name, 16)
            return "#" + name
        except ValueError:
            pass
    return default


def style_of(char):
    fg = to_hex(char.fg, DEFAULT_FG)
    bg = to_hex(char.bg, DEFAULT_BG)
    if char.reverse:
        fg, bg = bg, fg
    elif char.bold and char.fg in NAMED_COLORS and not char.fg.startswith("bright"):
        fg = NAMED_COLORS.get("bright" + char.fg, fg)
    return Style(fg, bg, bool(char.bold))


def snapshot(screen, caption, seconds):
    rows = [[(c.data, style_of(c)) for c in (screen.buffer[y][x] for x in range(COLS))]
            for y in range(ROWS)]
    cursor = None if screen.cursor.hidden else (screen.cursor.x, screen.cursor.y)
    return Frame(caption, seconds, rows, cursor)


def pump(master, stream, quiet=0.35, limit=4.0):
    """Feed pty output to the emulator until it has been quiet for `quiet` seconds."""
    deadline = time.time() + limit
    last_output = time.time()
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 0.05)
        if ready:
            try:
                data = os.read(master, 65536)
            except OSError:
                return
            if not data:
                return
            stream.feed(data)
            last_output = time.time()
        elif time.time() - last_output >= quiet:
            return


def make_sandbox(root):
    """Build a throwaway HOME with the plugin installed. Returns the environment dict."""
    home = os.path.join(root, "home")
    config = os.path.join(home, ".config", "byobu")
    os.makedirs(config)
    # A bare bash: no /etc/bash.bashrc, so no user@host or sudo banner in the picture.
    shell = os.path.join(root, "shell.sh")
    with open(shell, "w") as f:
        f.write("#!/bin/bash\nexec env PS1='$ ' bash --norc --noprofile\n")
    os.chmod(shell, 0o755)
    env = {
        "HOME": home, "PATH": "/usr/local/bin:/usr/bin:/bin",
        "TERM": "xterm-256color", "LANG": "C.UTF-8", "SHELL": shell,
        "BYOBU_CONFIG_DIR": config, "BYOBU_BACKEND": "tmux",
        "TMUX_TMPDIR": os.path.join(root, "tmux-tmp"),
    }
    os.makedirs(env["TMUX_TMPDIR"])
    subprocess.run([os.path.join(REPO, "install.sh"), "--no-rgb-fix", "--no-layout"],
                   env=env, check=True, stdout=subprocess.DEVNULL)
    # Answer byobu's first-run "ctrl-a mode" question up front. Screen mode makes
    # Ctrl+a the prefix, which is what the README describes.
    subprocess.run(["byobu-ctrl-a", "screen"], env=env, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return env


def record(env):
    """Run byobu on a pty, play SCENARIO, and return one Frame per step."""
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

    def become_session_leader():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    proc = subprocess.Popen(
        ["byobu"], stdin=slave, stdout=slave, stderr=slave, env=env,
        cwd=env["HOME"], preexec_fn=become_session_leader, close_fds=True,
    )
    os.close(slave)

    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)
    frames = []
    try:
        pump(master, stream, quiet=1.2, limit=12.0)  # let byobu start
        # Short right-hand status (no CPU/disk/host details), like the README example.
        # byobu rewrites `status` with its defaults while starting, so change it only
        # once it is up, then press F5 (reload) to apply it.
        with open(os.path.join(env["BYOBU_CONFIG_DIR"], "status"), "w") as f:
            f.write('tmux_left="logo"\ntmux_right="date time"\n')
        os.write(master, KEY_F5)
        pump(master, stream, quiet=1.5, limit=10.0)
        for caption, keys, seconds in SCENARIO:
            if keys:
                os.write(master, keys)
                pump(master, stream)
            # Print each frame's status bar so a wrong hint is visible in the log.
            print(f"[{caption}]\n   {screen.display[ROWS - 1].rstrip()}", flush=True)
            frames.append(snapshot(screen, caption, seconds))
    finally:
        for socket in ("byobu", "default"):
            subprocess.run(["tmux", "-L", socket, "kill-server"], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        proc.terminate()
    return frames


def style_runs(row):
    """Group a row's cells into runs that share one style: [(first_col, text, style)]."""
    runs = []
    for col, (char, style) in enumerate(row):
        if runs and runs[-1][2] == style:
            runs[-1][1].append(char)
        else:
            runs.append((col, [char], style))
    return [(col, "".join(chars), style) for col, chars, style in runs]


def frame_svg(index, frame):
    """The SVG elements of one frame, wrapped in <g id="f<index>">."""
    parts = [f'<g id="f{index}" class="f">']
    for y, row in enumerate(frame.rows):
        top = y * CELL_H
        baseline = top + CELL_H - 5
        for col, text, style in style_runs(row):
            left, width = col * CELL_W, len(text) * CELL_W
            if style.bg != DEFAULT_BG:
                parts.append(f'<rect x="{left:.1f}" y="{top:.1f}" width="{width:.1f}" '
                             f'height="{CELL_H}" fill="{style.bg}"/>')
            if text.strip():
                weight = ' font-weight="bold"' if style.bold else ""
                # textLength pins every run to the cell grid whatever font is used.
                parts.append(f'<text x="{left:.1f}" y="{baseline:.1f}" fill="{style.fg}"{weight} '
                             f'textLength="{width:.1f}" lengthAdjust="spacing" '
                             f'xml:space="preserve">{escape(text)}</text>')
    if frame.cursor:
        cx, cy = frame.cursor
        parts.append(f'<rect x="{cx * CELL_W + 0.5:.1f}" y="{cy * CELL_H + 0.5:.1f}" '
                     f'width="{CELL_W - 1:.1f}" height="{CELL_H - 1}" fill="none" '
                     f'stroke="{CURSOR_OUTLINE}"/>')
    # Caption strip: which key was just pressed.
    strip_top = ROWS * CELL_H
    parts.append(f'<rect x="0" y="{strip_top}" width="{COLS * CELL_W:.1f}" '
                 f'height="{CAPTION_HEIGHT}" fill="{CAPTION_BG}"/>')
    parts.append(f'<text x="14" y="{strip_top + 28}" fill="{CAPTION_FG}" font-weight="bold" '
                 f'font-size="{CAPTION_FONT_SIZE}" xml:space="preserve">'
                 f'{escape(frame.caption)}</text>')
    parts.append("</g>")
    return "\n".join(parts)


def animation_css(frames):
    """CSS that shows frame i only during its own slice of one looping cycle."""
    total = sum(f.seconds for f in frames)
    rules = [f".f{{opacity:0;animation:{total:.1f}s step-end infinite}}",
             "#f0{opacity:1}"]
    start = 0.0
    for i, frame in enumerate(frames):
        begin = 100 * start / total
        end = 100 * (start + frame.seconds) / total
        first = "0%{opacity:1}" if i == 0 else f"0%{{opacity:0}}{begin:.3f}%{{opacity:1}}"
        rules.append(f"#f{i}{{animation-name:k{i}}}"
                     f"@keyframes k{i}{{{first}{end:.3f}%{{opacity:0}}100%{{opacity:0}}}}")
        start += frame.seconds
    return "\n".join(rules)


def build_svg(frames):
    width = COLS * CELL_W
    height = ROWS * CELL_H + CAPTION_HEIGHT
    description = ("The status-bar hint changes as panes are split, the prefix key is pressed, "
                   "a pane is zoomed, copy mode is entered and typing into all panes is turned on.")
    body = "\n".join(frame_svg(i, f) for i, f in enumerate(frames))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {height:.0f}" '
            f'width="{width:.0f}" height="{height:.0f}" font-family="{FONT_FAMILY}" '
            f'font-size="{FONT_SIZE}" role="img" aria-labelledby="t d">\n'
            f"<title id=\"t\">byobu-keyhints demo</title>\n<desc id=\"d\">{escape(description)}</desc>\n"
            f"<style>\n{animation_css(frames)}\n</style>\n"
            f'<rect width="100%" height="100%" rx="6" fill="{DEFAULT_BG}"/>\n'
            f"{body}\n</svg>\n")


def main():
    out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="byobu-keyhints-demo.") as root:
        frames = record(make_sandbox(root))
    with open(out, "w", encoding="utf-8") as f:
        f.write(build_svg(frames))
    print(f"wrote {out}  {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
