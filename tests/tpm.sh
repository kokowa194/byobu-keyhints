#!/usr/bin/env bash
# Loads the plugin through a real tpm, set up exactly as the README tells byobu users to.
#   TPM_DIR=/path/to/a/tpm/checkout bash tests/tpm.sh
# CI checks tpm out at a pinned commit. Without TPM_DIR this test is skipped, so the
# default test run stays offline. Never touches your running byobu: every tmux server
# here lives in a throwaway TMUX_TMPDIR with a throwaway HOME.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${TPM_DIR:-}" ]; then
  echo "skip - TPM_DIR is not set (point it at a tpm checkout to run this test)"
  exit 0
fi
TPM_DIR="$(cd "$TPM_DIR" && pwd)"
WORK="$(mktemp -d)"
pass=0; fail=0
H=""   # HOME of the current scenario, set by start()

check() { # check <description> <expected substring> <actual value>
  if [[ "$3" == *"$2"* ]]; then pass=$((pass+1)); echo "ok   - $1"
  else fail=$((fail+1)); echo "FAIL - $1"; echo "       expected: *$2*"; echo "       actual:   $3"; fi
}
check_eq() {
  if [[ "$3" == "$2" ]]; then pass=$((pass+1)); echo "ok   - $1"
  else fail=$((fail+1)); echo "FAIL - $1"; echo "       expected: $2"; echo "       actual:   $3"; fi
}
# Run a command against the current scenario's tmux server. A bare `tmux` inside tpm
# reaches the same server: tpm runs under run-shell, which sets TMUX.
in_scenario() { env -u TMUX -u XDG_CONFIG_HOME -u BYOBU_CONFIG_DIR HOME="$H" TMUX_TMPDIR="$H/sock" "$@"; }
tx() { in_scenario tmux "$@"; }
cleanup() { for d in "$WORK"/*/; do H="${d%/}"; tx kill-server 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT

# start <scenario> <content of byobu's .tmux.conf>
start() {
  H="$WORK/$1"
  mkdir -p "$H/.config/byobu" "$H/.tmux/plugins" "$H/sock"
  # Both are already "installed", so tpm finds them locally and never downloads anything.
  ln -s "$TPM_DIR" "$H/.tmux/plugins/tpm"
  ln -s "$ROOT" "$H/.tmux/plugins/byobu-keyhints"
  printf '%s\n' "$2" > "$H/.config/byobu/.tmux.conf"
  # Stand-in for byobu's profiles/tmuxrc: byobu's own status bar first, then the user's
  # .tmux.conf last. byobu starts tmux with -f pointing at that file, so ~/.tmux.conf is
  # never read.
  printf '%s\n' "set -g status-right BYOBU_RIGHT" "source-file $H/.config/byobu/.tmux.conf" > "$H/tmuxrc"
  tx -f "$H/tmuxrc" new -d -s t -x 200 -y 40
}

# The README's tpm block is the config under test, so the instructions cannot drift
# away from what actually works.
readme_config="$(awk '/<!-- tpm-config:/ { found = 1; next }
  found && /^```tmux/ { inside = 1; next }
  inside && /^```/ { exit }
  inside' "$ROOT/README.md")"
echo "# README's tpm block"
check "README has a tpm block that runs tpm" "run '~/.tmux/plugins/tpm/tpm'" "$readme_config"

echo "# README config through a real tpm"
start readme "$readme_config"
check_eq "hint is prepended to byobu's status-right exactly once" '#{E:@byobu_hint}BYOBU_RIGHT' "$(tx show -gv status-right)"
check "single pane shows the split hint" "Ctrl+F2:Split left/right" "$(tx display -p -t t '#{E:@byobu_hint}')"
check_eq "escape-time is not 50 by default" "0" "$(tx show -sv escape-time | grep -c '^50$')"
# prefix + I runs this. The plugin is already in place, so a found plugin is reported as
# installed; a plugin tpm cannot see is not listed at all.
check "tpm's installer sees the plugin (prefix + I)" 'Already installed "byobu-keyhints"' "$(in_scenario "$TPM_DIR/bin/install_plugins" 2>&1)"
tx kill-server 2>/dev/null

echo "# README config with the rgb fix line before run"
start rgbfix "set -g @byobu_fix_osc_garbage 1
$readme_config"
check_eq "escape-time becomes 50" "50" "$(tx show -sv escape-time)"
tx kill-server 2>/dev/null

echo "# Why the README says @tpm_plugins: @plugin lines in byobu's .tmux.conf are not found"
start plugin_lines "set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'kokowa194/byobu-keyhints'
run '~/.tmux/plugins/tpm/tpm'"
check_eq "the plugin is not loaded" "BYOBU_RIGHT" "$(tx show -gv status-right)"
check_eq "tpm's installer does not see it either" "0" "$(in_scenario "$TPM_DIR/bin/install_plugins" 2>&1 | grep -c 'byobu-keyhints')"
tx kill-server 2>/dev/null

echo
echo "Result: $pass passed / $fail failed"
[ "$fail" -eq 0 ]
