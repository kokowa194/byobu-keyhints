#!/usr/bin/env bash
# Append one block to byobu's .tmux.conf that sources plugin.tmux. Idempotent.
#
# Usage: ./install.sh [--with-rgb-fix | --no-rgb-fix] [--with-layout | --no-layout]
#   Two optional features are asked about interactively (default "no"):
#     rgb-garbage fix  escape-time 50
#     default layout   new byobu sessions start as a 2x2 split (writes windows.tmux)
#   Pass a flag to skip a question; without a terminal the default is "no".
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly MARK_BEGIN="# >>> byobu-keyhints >>>"
readonly MARK_END="# <<< byobu-keyhints <<<"
# This project was called byobu-plugin-mine before v0.1.0 was published.
readonly LEGACY_MARK_BEGIN="# >>> byobu-plugin-mine >>>"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PLUGIN_DIR

# yes_no <flag-given: yes|no|""> <prompt>: flag > prompt > default (no).
yes_no() {
  case "$1" in
    yes) return 0 ;;
    no) return 1 ;;
  esac
  [ -t 0 ] || return 1
  local answer
  read -r -p "$2 [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]]
}

RGB_FLAG=""
LAYOUT_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --with-rgb-fix) RGB_FLAG=yes ;;
    --no-rgb-fix) RGB_FLAG=no ;;
    --with-layout) LAYOUT_FLAG=yes ;;
    --no-layout) LAYOUT_FLAG=no ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

CONF="$(config_dir)/.tmux.conf"
mkdir -p "$(dirname "$CONF")"
touch "$CONF"

if grep -qF "$MARK_BEGIN" "$CONF"; then
  echo "Already installed: $CONF"
  echo "To change options, run ./uninstall.sh and then ./install.sh again."
  exit 0
fi

if grep -qF "$LEGACY_MARK_BEGIN" "$CONF"; then
  echo "An old byobu-plugin-mine block is in $CONF." >&2
  echo "Run ./uninstall.sh first (it removes the old block too), then ./install.sh again." >&2
  exit 1
fi

RGB_FIX=0
if yes_no "$RGB_FLAG" "Also enable the rgb-garbage fix (escape-time 50)? Only needed if junk like 11;rgb:... shows up at the prompt."; then RGB_FIX=1; fi

LAYOUT=0
WINDOWS_FILE="$(dirname "$CONF")/windows.tmux"
if yes_no "$LAYOUT_FLAG" "Also start every new byobu session as a 2x2 split (writes $WINDOWS_FILE)?"; then
  if [[ "$HOME" =~ [[:space:]] ]]; then
    echo "HOME contains whitespace, which windows.tmux cannot express. Layout not installed." >&2
    exit 1
  fi
  # Never overwrite a windows.tmux the user wrote themselves; check before touching anything.
  if [ -s "$WINDOWS_FILE" ] && [ "$(cat "$WINDOWS_FILE")" != "$(layout_line)" ]; then
    echo "$WINDOWS_FILE already exists and is not ours. Not overwriting it." >&2
    echo "Move it away or merge by hand, then run ./install.sh --with-layout again." >&2
    exit 1
  fi
  LAYOUT=1
fi

# Nothing to protect in an empty file, so skip the backup (and avoid piling up 0-byte .bak files).
if [ -s "$CONF" ]; then cp "$CONF" "$CONF.bak-$(date +%Y%m%d%H%M%S)"; fi
{
  echo "$MARK_BEGIN"
  if [ "$RGB_FIX" -eq 1 ]; then echo "set -g @byobu_fix_osc_garbage 1"; fi
  echo "source-file -q \"$PLUGIN_DIR/plugin.tmux\""
  echo "$MARK_END"
} >> "$CONF"
if [ "$LAYOUT" -eq 1 ]; then layout_line > "$WINDOWS_FILE"; fi

echo "Installed: $CONF (rgb-garbage fix: $([ "$RGB_FIX" -eq 1 ] && echo on || echo off), 2x2 layout: $([ "$LAYOUT" -eq 1 ] && echo on || echo off))"
if [ "$LAYOUT" -eq 1 ]; then
  echo "Layout applies to NEW byobu sessions only. byobu now always starts a new session instead of offering to attach."
fi
echo "Press F5 inside byobu to apply (newly started byobu sessions pick it up automatically)."
