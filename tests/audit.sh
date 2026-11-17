#!/usr/bin/env bash
# Checks the claims made in the README, so you don't have to take them on trust:
#   - nothing here uses the network, sudo, eval or recursive delete
#   - the .tmux files run no shell commands (the "zero shell" claim)
#   - install.sh / uninstall.sh only touch byobu's config directory
#   - every tracked file is plain text, and only the tpm entry point is an executable .tmux
#   bash tests/audit.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPHOME="$(mktemp -d)"
trap 'rm -rf "$TMPHOME"' EXIT
pass=0; fail=0

check_eq() { # check_eq <description> <expected> <actual>
  if [[ "$3" == "$2" ]]; then pass=$((pass+1)); echo "ok   - $1"
  else fail=$((fail+1)); echo "FAIL - $1"; echo "       expected: $2"; echo "       actual:   $3"; fi
}
# Code lines only: drop comment-only lines so prose cannot trigger a match.
code() { grep -hv '^[[:space:]]*#' "$@"; }

SCRIPTS=("$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/lib.sh" "$ROOT/byobu-keyhints.tmux")
TMUX_FILES=("$ROOT/plugin.tmux" "$ROOT"/conf/*.tmux)

echo "# Shell scripts: no network, privilege escalation or dangerous commands"
check_eq "no network commands" "" \
  "$(code "${SCRIPTS[@]}" | grep -nwE 'curl|wget|nc|ncat|ssh|scp|rsync|ftp|telnet|git' | head -3)"
check_eq "no sudo / su / doas" "" \
  "$(code "${SCRIPTS[@]}" | grep -nwE 'sudo|su|doas' | head -3)"
check_eq "no eval / base64 / chmod / chown" "" \
  "$(code "${SCRIPTS[@]}" | grep -nwE 'eval|base64|chmod|chown' | head -3)"
check_eq "no recursive rm" "" \
  "$(code "${SCRIPTS[@]}" | grep -nE 'rm[[:space:]]+-[a-zA-Z]*[rR]' | head -3)"
check_eq "no URLs in shell scripts or tmux files" "" \
  "$(code "${SCRIPTS[@]}" "${TMUX_FILES[@]}" | grep -nE 'https?://|ftp://' | head -3)"

echo "# tmux files: no shell commands"
check_eq "no run-shell / run / #(...)" "" \
  "$(code "${TMUX_FILES[@]}" | grep -nE '(^|[[:space:];])(run-shell|run)[[:space:]]|#\(' | head -3)"
# if-shell without -F would hand its condition to /bin/sh.
check_eq "every if-shell uses -F (format only)" "" \
  "$(code "${TMUX_FILES[@]}" | grep -n 'if-shell' | grep -v 'if-shell -F' | head -3)"

echo "# install.sh / uninstall.sh touch only byobu's config directory"
# Run both against a throwaway HOME and list every file that appeared.
mkdir -p "$TMPHOME/home"
HOME="$TMPHOME/home" env -u BYOBU_CONFIG_DIR -u XDG_CONFIG_HOME bash "$ROOT/install.sh" --with-rgb-fix --with-layout </dev/null >/dev/null 2>&1
after_install="$(cd "$TMPHOME" && find . -type f | sort)"
check_eq "install creates only .tmux.conf and windows.tmux (no backup: it started empty)" \
  "./home/.config/byobu/.tmux.conf
./home/.config/byobu/windows.tmux" "$after_install"
HOME="$TMPHOME/home" env -u BYOBU_CONFIG_DIR -u XDG_CONFIG_HOME bash "$ROOT/uninstall.sh" >/dev/null 2>&1
check_eq "uninstall leaves .tmux.conf empty again" "0" "$(wc -c < "$TMPHOME/home/.config/byobu/.tmux.conf" | tr -d ' ')"
check_eq "uninstall leaves windows.tmux empty again" "0" "$(wc -c < "$TMPHOME/home/.config/byobu/windows.tmux" | tr -d ' ')"
check_eq "nothing was written outside the throwaway HOME's byobu directory" "" \
  "$(cd "$TMPHOME" && find . -type f ! -path './home/.config/byobu/*' | head -3)"

echo "# Files are plain text; file modes"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  binary="$(git -C "$ROOT" ls-files | while read -r f; do grep -qI . "$ROOT/$f" 2>/dev/null || echo "$f"; done)"
  check_eq "every tracked file is text" "" "$binary"
  # tpm tries to execute every *.tmux file in the top directory. Only the tpm entry point
  # may be executable; plugin.tmux and conf/*.tmux are tmux configs, not scripts.
  executable_tmux="$(git -C "$ROOT" ls-files -s -- '*.tmux' | awk '$1 == "100755" { print $4 }')"
  check_eq "byobu-keyhints.tmux is the only executable .tmux file" "byobu-keyhints.tmux" "$executable_tmux"
else
  echo "skip - not a git checkout"
fi

echo "# shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  check_eq "shellcheck is clean" "" "$(shellcheck "${SCRIPTS[@]}" "$ROOT"/tests/*.sh 2>&1 | head -20)"
else
  echo "skip - shellcheck is not installed (CI runs it)"
fi

echo
echo "Result: $pass passed / $fail failed"
[ "$fail" -eq 0 ]
