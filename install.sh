#!/usr/bin/env bash
# Append one block to byobu's .tmux.conf that sources plugin.tmux. Idempotent.
#
# Usage: ./install.sh [--with-rgb-fix | --no-rgb-fix]
#   The optional rgb-garbage fix (escape-time 50) is asked about interactively.
#   Pass a flag to skip the question; without a terminal the default is "no".
set -euo pipefail

readonly MARK_BEGIN="# >>> byobu-keyhints >>>"
readonly MARK_END="# <<< byobu-keyhints <<<"
# This project was called byobu-plugin-mine before v0.1.0 was published.
readonly LEGACY_MARK_BEGIN="# >>> byobu-plugin-mine >>>"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PLUGIN_DIR

# Same lookup order as byobu: ~/.byobu if it exists, otherwise the XDG location.
config_dir() {
  if [ -n "${BYOBU_CONFIG_DIR:-}" ]; then echo "$BYOBU_CONFIG_DIR"
  elif [ -d "$HOME/.byobu" ]; then echo "$HOME/.byobu"
  else echo "${XDG_CONFIG_HOME:-$HOME/.config}/byobu"
  fi
}

# Decide whether to enable the optional rgb-garbage fix: flag > prompt > default (no).
want_rgb_fix() {
  case "${1:-}" in
    --with-rgb-fix) return 0 ;;
    --no-rgb-fix) return 1 ;;
    "") ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  [ -t 0 ] || return 1
  local answer
  read -r -p "Also enable the rgb-garbage fix (escape-time 50)? Only needed if junk like 11;rgb:... shows up at the prompt. [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]]
}

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
if want_rgb_fix "${1:-}"; then RGB_FIX=1; fi

# Nothing to protect in an empty file, so skip the backup (and avoid piling up 0-byte .bak files).
if [ -s "$CONF" ]; then cp "$CONF" "$CONF.bak-$(date +%Y%m%d%H%M%S)"; fi
{
  echo "$MARK_BEGIN"
  if [ "$RGB_FIX" -eq 1 ]; then echo "set -g @byobu_fix_osc_garbage 1"; fi
  echo "source-file -q \"$PLUGIN_DIR/plugin.tmux\""
  echo "$MARK_END"
} >> "$CONF"

echo "Installed: $CONF (rgb-garbage fix: $([ "$RGB_FIX" -eq 1 ] && echo on || echo off))"
echo "Press F5 inside byobu to apply (newly started byobu sessions pick it up automatically)."
