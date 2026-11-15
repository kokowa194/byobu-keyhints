#!/usr/bin/env bash
# Never touches your running byobu: starts tmux servers on private sockets.
#   bash tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="bpm-test-$$"
OUTER="bpm-outer-$$"
TMPHOME="$(mktemp -d)"
pass=0; fail=0

t()  { env -u TMUX tmux -L "$SOCK" "$@"; }
to() { env -u TMUX tmux -L "$OUTER" "$@"; }
cleanup() { t kill-server 2>/dev/null; to kill-server 2>/dev/null; rm -rf "$TMPHOME"; }
trap cleanup EXIT

check() { # check <description> <expected substring> <actual value>
  if [[ "$3" == *"$2"* ]]; then pass=$((pass+1)); echo "ok   - $1"
  else fail=$((fail+1)); echo "FAIL - $1"; echo "       expected: *$2*"; echo "       actual:   $3"; fi
}
check_eq() {
  if [[ "$3" == "$2" ]]; then pass=$((pass+1)); echo "ok   - $1"
  else fail=$((fail+1)); echo "FAIL - $1"; echo "       expected: $2"; echo "       actual:   $3"; fi
}
hint() { t display -p -t t '#{E:@byobu_hint}'; }

echo "# Loading the config"
t -f /dev/null new -d -s t -x 200 -y 40
t set -g prefix C-a                         # same prefix as byobu
t set -g status-right 'BYOBU_RIGHT'          # stand-in for byobu's status-right
t source-file "$ROOT/plugin.tmux"
t source-file "$ROOT/plugin.tmux"            # sourcing twice must not duplicate
check_eq "hint is prepended to status-right exactly once" '#{E:@byobu_hint}BYOBU_RIGHT' "$(t show -gv status-right)"
check_eq "escape-time is not 50 by default" "0" "$(t show -sv escape-time | grep -c '^50$')"
t set -g @byobu_fix_osc_garbage 1
t source-file "$ROOT/plugin.tmux"
check_eq "escape-time becomes 50 when @byobu_fix_osc_garbage is 1" "50" "$(t show -sv escape-time)"
check_eq "hint is still prepended exactly once after re-sourcing" '#{E:@byobu_hint}BYOBU_RIGHT' "$(t show -gv status-right)"

echo "# Hint per situation"
check "single pane: split hint"           "Ctrl+F2:Split left/right" "$(hint)"
t split-window -h -t t
check "several panes: move hint"          "Shift+Arrows:Move"        "$(hint)"
check "several panes: prefix is spelled out" "Ctrl+a then Ctrl+Arrows:Resize" "$(hint)"
t resize-pane -Z -t t
check "zoomed"                              "[Zoomed] Shift+F11:Unzoom" "$(hint)"
t resize-pane -Z -t t
t setw -t t synchronize-panes on
check "sync-panes shows a warning"        "WARNING: typing goes to ALL panes" "$(hint)"
t setw -t t synchronize-panes off
t copy-mode -t t
check "copy mode"                           "Space:Select"             "$(hint)"
t send-keys -t t -X cancel
t set -g @byobu_hint_enabled 0
check_eq "hint is empty when disabled"        ""                 "$(hint)"
t set -g @byobu_hint_enabled 1

echo "# Real client rendering (prefix state, H key)"
# Attach to the inner server from a pane of an outer tmux so a real status bar is drawn
to -f /dev/null new -d -s o -x 200 -y 12 "env -u TMUX tmux -L $SOCK attach -t t"
for _ in $(seq 50); do [ -n "$(t list-clients -F '#{client_name}')" ] && break; sleep 0.1; done
client="$(t list-clients -F '#{client_name}' | head -1)"
check "inner client attached" "/" "$client"
to send-keys -t o C-a; sleep 0.3
check "prefix hint shown while the prefix is held" "[Ctrl+a] %:Split left/right" "$(t list-clients -t t -F '#{E:@byobu_hint}')"   # display -p -c fails on tmux 3.2a
echo "       bottom row: $(to capture-pane -p -t o | tail -1 | sed 's/ *$//')"
to send-keys -t o H; sleep 0.3
check_eq "prefix + H turns the hint off" "0" "$(t show -gv @byobu_hint_enabled)"
to send-keys -t o C-a H; sleep 0.3
check_eq "prefix + H again turns it back on" "1" "$(t show -gv @byobu_hint_enabled)"

echo "# ASCII only in tmux config"
# Wide characters break status-bar width math, so .tmux files must stay ASCII.
non_ascii="$(grep -nP '[^\x00-\x7F]' "$ROOT"/plugin.tmux "$ROOT"/conf/*.tmux | head -3)"
check_eq "no non-ASCII character in plugin.tmux / conf/*.tmux" "" "$non_ascii"

echo "# install.sh / uninstall.sh"
export BYOBU_CONFIG_DIR="$TMPHOME/byobu"
mkdir -p "$BYOBU_CONFIG_DIR"; echo "set -g mouse on" > "$BYOBU_CONFIG_DIR/.tmux.conf"
# stdin is /dev/null so install.sh never waits at its y/N prompt, even when run from a terminal
bash "$ROOT/install.sh" </dev/null >/dev/null; bash "$ROOT/install.sh" </dev/null >/dev/null
check_eq "running install twice leaves one block" "1" "$(grep -c '>>> byobu-keyhints' "$BYOBU_CONFIG_DIR/.tmux.conf")"
check_eq "no terminal and no flag: rgb fix is off" "0" "$(grep -c '@byobu_fix_osc_garbage' "$BYOBU_CONFIG_DIR/.tmux.conf")"
check "sources the absolute path of plugin.tmux" "source-file -q \"$ROOT/plugin.tmux\"" "$(cat "$BYOBU_CONFIG_DIR/.tmux.conf")"
check "creates a backup when .tmux.conf has content" ".tmux.conf.bak-" "$(ls -a "$BYOBU_CONFIG_DIR")"
bash "$ROOT/uninstall.sh" >/dev/null
check_eq "uninstall restores the original content" "set -g mouse on" "$(cat "$BYOBU_CONFIG_DIR/.tmux.conf")"
bash "$ROOT/install.sh" --with-rgb-fix </dev/null >/dev/null
check "--with-rgb-fix writes the option" "set -g @byobu_fix_osc_garbage 1" "$(cat "$BYOBU_CONFIG_DIR/.tmux.conf")"
bash "$ROOT/uninstall.sh" >/dev/null
check_eq "uninstall also removes the option line" "set -g mouse on" "$(cat "$BYOBU_CONFIG_DIR/.tmux.conf")"
bash "$ROOT/install.sh" --no-rgb-fix </dev/null >/dev/null
check_eq "--no-rgb-fix does not write the option" "0" "$(grep -c '@byobu_fix_osc_garbage' "$BYOBU_CONFIG_DIR/.tmux.conf")"
bash "$ROOT/uninstall.sh" >/dev/null
check_eq "bad option is rejected" "2" "$(bash "$ROOT/install.sh" --bogus </dev/null >/dev/null 2>&1; echo $?)"
# An empty (or missing) .tmux.conf has nothing worth backing up.
: > "$BYOBU_CONFIG_DIR/.tmux.conf"; rm -f "$BYOBU_CONFIG_DIR"/.tmux.conf.bak-*
bash "$ROOT/install.sh" </dev/null >/dev/null
backups=("$BYOBU_CONFIG_DIR"/.tmux.conf.bak-*)   # unmatched glob stays literal, so test the first entry
[ -e "${backups[0]}" ] || backups=()
check_eq "no backup is made for an empty .tmux.conf" "0" "${#backups[@]}"
bash "$ROOT/uninstall.sh" >/dev/null
# A block written under the old name (byobu-plugin-mine) must still be removable,
# and install.sh must not stack a second block on top of it.
printf '%s\n' "set -g mouse on" "# >>> byobu-plugin-mine >>>" 'source-file -q "/old/plugin.tmux"' "# <<< byobu-plugin-mine <<<" > "$BYOBU_CONFIG_DIR/.tmux.conf"
check_eq "install refuses while an old-name block exists" "1" "$(bash "$ROOT/install.sh" </dev/null >/dev/null 2>&1; echo $?)"
bash "$ROOT/uninstall.sh" >/dev/null
check_eq "uninstall removes an old-name block" "set -g mouse on" "$(cat "$BYOBU_CONFIG_DIR/.tmux.conf")"

echo "# Default 2x2 layout (--with-layout)"
# HOME is a throwaway directory so the pane cwd check proves the path comes from $HOME.
export HOME="$TMPHOME/home"; mkdir -p "$HOME"
: > "$BYOBU_CONFIG_DIR/.tmux.conf"; : > "$BYOBU_CONFIG_DIR/windows.tmux"
bash "$ROOT/install.sh" --with-layout </dev/null >/dev/null
check_eq "windows.tmux is exactly one line" "1" "$(wc -l < "$BYOBU_CONFIG_DIR/windows.tmux" | tr -d ' ')"
check_eq "windows.tmux has no quotes or comments" "0" "$(grep -c "[\"'#]" "$BYOBU_CONFIG_DIR/windows.tmux")"
# Start it the way byobu does: tmux $(cat windows.tmux) -- word-split, no shell parsing.
# Only -d/-x/-y are added so it can run without a terminal.
LAYOUT_SOCK="bpm-layout-$$"
# shellcheck disable=SC2046
env -u TMUX tmux -L "$LAYOUT_SOCK" -f /dev/null $(sed 's/^new-session/new-session -d -x 160 -y 40/' "$BYOBU_CONFIG_DIR/windows.tmux")
panes="$(env -u TMUX tmux -L "$LAYOUT_SOCK" list-panes -F '#{pane_left},#{pane_top} #{pane_current_path} #{pane_active}')"
env -u TMUX tmux -L "$LAYOUT_SOCK" kill-server 2>/dev/null
check_eq "four panes in a 2x2 grid, all in HOME, focus on top-left" \
"0,0 $HOME 1
0,21 $HOME 0
81,0 $HOME 0
81,21 $HOME 0" "$panes"
bash "$ROOT/install.sh" --with-layout </dev/null >/dev/null 2>&1   # already installed: no-op
check_eq "windows.tmux is unchanged by a second install" "1" "$(wc -l < "$BYOBU_CONFIG_DIR/windows.tmux" | tr -d ' ')"
bash "$ROOT/uninstall.sh" >/dev/null
check_eq "uninstall empties windows.tmux" "0" "$(wc -c < "$BYOBU_CONFIG_DIR/windows.tmux" | tr -d ' ')"
echo "set-option -g status off" > "$BYOBU_CONFIG_DIR/windows.tmux"   # a windows.tmux the user wrote
check_eq "install --with-layout refuses to overwrite a user's windows.tmux" "1" "$(bash "$ROOT/install.sh" --with-layout </dev/null >/dev/null 2>&1; echo $?)"
check_eq "...and the user's file is untouched" "set-option -g status off" "$(cat "$BYOBU_CONFIG_DIR/windows.tmux")"
check_eq "...and nothing else was installed" "0" "$(grep -c '>>> byobu-keyhints' "$BYOBU_CONFIG_DIR/.tmux.conf")"
bash "$ROOT/install.sh" --no-layout </dev/null >/dev/null
bash "$ROOT/uninstall.sh" >/dev/null
check_eq "uninstall leaves a user's windows.tmux alone" "set-option -g status off" "$(cat "$BYOBU_CONFIG_DIR/windows.tmux")"

echo
echo "Result: $pass passed / $fail failed"
[ "$fail" -eq 0 ]
