#!/usr/bin/env bash
# Remove only the block(s) that install.sh appended to .tmux.conf,
# and windows.tmux if (and only if) it is exactly the layout install.sh wrote.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Current name first; byobu-plugin-mine is the name used before v0.1.0 was published.
readonly NAMES=(byobu-keyhints byobu-plugin-mine)

CONF="$(config_dir)/.tmux.conf"
WINDOWS_FILE="$(dirname "$CONF")/windows.tmux"
if [ ! -f "$CONF" ]; then
  echo "Not installed: $CONF"
  exit 0
fi

removed=0
for name in "${NAMES[@]}"; do
  begin="# >>> $name >>>"
  end="# <<< $name <<<"
  grep -qF "$begin" "$CONF" || continue
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$CONF" > "$tmp"
  cat "$tmp" > "$CONF"   # overwrite instead of mv: keeps the file's permissions and symlinks
  rm -f "$tmp"
  removed=1
done

if [ -s "$WINDOWS_FILE" ] && [ "$(cat "$WINDOWS_FILE")" = "$(layout_line)" ]; then
  : > "$WINDOWS_FILE"   # empty it (byobu ignores an empty file) instead of deleting
  removed=1
  echo "Removed the 2x2 layout from $WINDOWS_FILE"
fi

if [ "$removed" -eq 0 ]; then
  echo "Not installed: $CONF"
  exit 0
fi

echo "Uninstalled: $CONF"
echo "Restart byobu to fully revert (F5 leaves escape-time and the key bindings in place)."
