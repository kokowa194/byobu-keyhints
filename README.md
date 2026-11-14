# byobu-keyhints

[![test](https://github.com/kokowa194/byobu-keyhints/actions/workflows/test.yml/badge.svg)](https://github.com/kokowa194/byobu-keyhints/actions/workflows/test.yml)
![license: MIT](https://img.shields.io/badge/license-MIT-blue)
![byobu: 6.11](https://img.shields.io/badge/byobu-6.11-informational)
![tmux: 3.2+](https://img.shields.io/badge/tmux-3.2%2B-1BB91F)
![platform: WSL2 Ubuntu 24.04](https://img.shields.io/badge/platform-WSL2_Ubuntu_24.04-orange)
![shell: bash only](https://img.shields.io/badge/shell-bash_only-lightgrey)
![no sudo, no network](https://img.shields.io/badge/install-no_sudo%2C_no_network-success)

A small plugin for byobu (tmux backend). v0.1.0

1. **Context-sensitive shortcut hints**: the status bar shows the keys that work in your current situation.
2. **Optional: rgb-garbage fix**: stops strings like `11;rgb:1717/1414/2121` from leaking into your prompt. Off by default; `install.sh` asks whether you want it.

```
 0:bash 1:vim*   Shift+Arrows:Move Ctrl+a then Ctrl+Arrows:Resize Shift+F11:Zoom Ctrl+F6:Close  2x3.0GHz 11-14 21:30
```

## When the hint changes

Checked from the top; the first match wins.

| Situation | Hint shown |
|---|---|
| Right after the prefix (`Ctrl+a` / `F12`) | `%` split left/right / `\|` split top/bottom / arrows move / `z` zoom / `[` copy / `d` detach |
| Copy mode (`F7`) | select, rectangle, copy, search, quit, paste |
| Typing into all panes (`Alt+F9`) | a **red warning** and the key to turn it off |
| Zoomed (`Shift+F11`) | the key to unzoom |
| Several panes in the window | move, resize, zoom, close |
| A single pane | split, new window, switch window, rename |

The plugin calls no shell scripts. The hint is built purely from tmux format conditionals,
so it costs nothing and switches the instant you press a key.

**Toggle the hint on/off: `prefix`, then `H`**

## Install

### Requirements

- byobu with the tmux backend, and tmux 3.2 or newer (the plugin uses `current_file`; only tmux 3.4 has been tested). Pick tmux with `byobu-select-backend`.
- bash. No sudo and no extra packages.

```bash
tmux -V                      # 3.2 or newer?
cat ~/.config/byobu/backend  # should contain BYOBU_BACKEND=tmux
```

### Steps

```bash
# 1. Put it anywhere (git clone or just copy the folder)
git clone https://github.com/kokowa194/byobu-keyhints.git ~/.local/share/byobu-keyhints
cd ~/.local/share/byobu-keyhints

# 2. Install
./install.sh
```

`install.sh` does three things. Running it again never adds a second block.

1. Backs up your existing `.tmux.conf` (as `.tmux.conf.bak-<timestamp>`; skipped if the file is empty).
2. Asks whether to enable the optional [rgb-garbage fix](#the-rgb-garbage-fix-optional) (default: no).
3. Appends a block to byobu's `.tmux.conf` that loads this plugin:

```tmux
# >>> byobu-keyhints >>>
set -g @byobu_fix_osc_garbage 1    # only if you answered "y"
source-file -q "/home/<you>/.local/share/byobu-keyhints/plugin.tmux"
# <<< byobu-keyhints <<<
```

To skip the question, pass a flag:

```bash
./install.sh --with-rgb-fix   # enable the fix
./install.sh --no-rgb-fix     # don't enable it
```

Without a terminal (for example in a script) and without a flag, the fix is left off.
To change the choice later, run `./uninstall.sh` and then `./install.sh` again, or add or remove the `set -g @byobu_fix_osc_garbage 1` line by hand.

The block goes into `~/.byobu/.tmux.conf` if `~/.byobu` exists, otherwise into `~/.config/byobu/.tmux.conf` (the same lookup order as byobu).

### Apply it

- In a running byobu, press **`F5`**.
- Newly started byobu sessions pick it up automatically.
- Changes to `escape-time` may not take effect in an already running session. If so, quit byobu and start it again.

### Check that it works

The status bar's right side should show something like `Ctrl+F2:Split left/right Shift+F2:Split top/bottom ...`.
Press `C-a` and the hint switches to the prefix view.

If you enabled the rgb fix, run this inside byobu:

```bash
tmux show -sv escape-time   # 50 means the fix is active
```

### Manual install

You can skip the script. Add this line to `.tmux.conf` (and, optionally, the rgb fix before it):

```tmux
set -g @byobu_fix_osc_garbage 1    # optional
source-file -q "/absolute/path/to/byobu-keyhints/plugin.tmux"
```

### If you move the folder

The line in `.tmux.conf` is an absolute path, so moving the folder breaks it. Because of `-q` there is no error; the hint just disappears.
Run `./uninstall.sh` and `./install.sh` again from the new location.

### Troubleshooting

| Symptom | What to check |
|---|---|
| No hint appears | Did you press `F5`? Did you turn it off with `prefix` then `H`? If `~/.byobu` exists, it takes priority and the block was installed there. |
| `escape-time` is still 0 | You may not have enabled the rgb fix (see the install steps). If you did, quit byobu and start it again. |
| The right end is cut off and the first key names are missing | The terminal is too narrow. With several panes or after pressing the prefix you need about 140 columns. Shorten the text (see [Customize](#customize)). |

### Uninstall

```bash
./uninstall.sh
```

Removes only the block that `install.sh` added, leaving the rest of `.tmux.conf` untouched.
To fully restore `escape-time` and the key bindings, restart byobu.

## The rgb-garbage fix (optional)

I only saw this problem in my own setup (WSL2 + Windows Terminal), so it is opt-in. If you never see junk at your prompt, you don't need it.

Vim and shells sometimes ask the terminal "what is your background color?" (OSC 11).
Windows Terminal replies with `ESC ] 11;rgb:RRRR/GGGG/BBBB`.

byobu's stock profile sets `escape-time 0`.
When the reply arrives split into pieces through WSL, tmux treats the leading ESC as a lone keypress,
and the rest (`11;rgb:...`) is typed into the shell as ordinary characters.

With the fix enabled, the plugin sets `escape-time` to 50 ms.
If junk still appears, raise the value by adding `set -sg escape-time 100` at the end of `~/.config/byobu/.tmux.conf`.

The same symptom has been reported outside byobu, for example in
[microsoft/terminal #18004](https://github.com/microsoft/terminal/issues/18004).

## Windows Terminal conflicts

These byobu keys are often taken by Windows Terminal's defaults, so the hints do not show them.

| byobu key | Conflicting Windows Terminal default | Key the hint shows instead |
|---|---|---|
| `Alt+Shift+Arrows` (resize pane) | WT pane resize | `prefix`, then `Ctrl+Arrows` |
| `Alt+Left/Right` (switch window) | WT pane focus movement | `F3` / `F4` |

## Customize

Put these **after** the plugin block in `~/.config/byobu/.tmux.conf` to override the defaults.

```tmux
set -g @byobu_hint_style "#[fg=colour45]"                  # color
set -g @byobu_hint_single "Ctrl+F2:Split F2:New window"    # text for a single pane
set -g @byobu_hint_enabled 0                               # hidden by default
```

See `conf/hints.tmux` for every text variable.
The hint text is **ASCII only** (keys are spelled `Ctrl+`, `Shift+`, `Alt+`) so that status-bar width calculation stays correct.
Avoid non-ASCII characters and symbols such as arrows in your own text too.

## Verify it yourself

The plugin is small enough to read in a few minutes (about 160 lines in total, comments included), but you can also check the claims above mechanically.
Both scripts need only bash and tmux. Neither touches your running byobu or your real config.

```bash
bash tests/audit.sh   # are the README's "no network / no sudo / only touches byobu's config" claims true?
bash tests/run.sh     # does the plugin behave as described?
```

`tests/audit.sh` checks that:

- the shell scripts contain no network commands, `sudo`, `eval`, `base64`, `chmod`/`chown` or recursive `rm`, and no URLs appear in any script or `.tmux` file;
- the `.tmux` files run no shell commands (no `run-shell`, no `#(...)`, and every `if-shell` uses `-F`);
- `install.sh` / `uninstall.sh`, run against a throwaway `HOME`, create only `.config/byobu/.tmux.conf`, and uninstall leaves it empty again;
- every tracked file is plain text;
- `shellcheck` is clean (skipped if it is not installed).

`tests/run.sh` starts tmux servers on private sockets and checks the hint for each situation, real rendering when the prefix is pressed, the `H` key, the optional rgb fix, and install/uninstall.
It also fails if a non-ASCII character appears in any `.tmux` file.

GitHub Actions runs both on Ubuntu 22.04 (tmux 3.2a, the documented minimum) and Ubuntu 24.04 (tmux 3.4); see the `test` badge at the top.

## Tested on

WSL2 Ubuntu 24.04 / byobu 6.11 / tmux 3.4 / Windows Terminal

## License

MIT
