# Show context-sensitive shortcut hints at the left edge of the right status bar.
#
# Design: no shell scripts. Everything is built from tmux format conditionals.
#   -> zero process-spawn cost, and the hint switches the instant a key is pressed.
#
# Key choice (Windows Terminal + WSL):
#   byobu keys that Windows Terminal grabs by default are NOT shown as hints.
#     Alt+Shift+Arrows ... taken by WT pane resize -> hint "Ctrl+a then Ctrl+Arrows" instead
#     Alt+Arrows       ... may be taken by WT pane focus movement
#
# Wording: split-window -h puts panes side by side (left/right), -v stacks them
#   (top/bottom). "vertical/horizontal split" is read both ways by different
#   people, so the hints describe the resulting layout instead.
#
# All text here is plain ASCII on purpose (wide characters break status-bar width
# math). tests/run.sh fails if a non-ASCII character sneaks into any .tmux file.
# Keys are spelled out (Ctrl+, Shift+, Alt+) rather than tmux notation (C-, S-, M-).

# ---- Settings (override in ~/.config/byobu/.tmux.conf, after the plugin block) ----
set -g @byobu_hint_enabled 1
set -g @byobu_hint_style "#[fg=colour222]"

# ---- Hint text per situation (highest priority first) ----
# #{s/C-/Ctrl+/:prefix} turns tmux's "C-a" into "Ctrl+a".
# 1. Right after pressing the prefix (Ctrl+a / F12)
set -g @byobu_hint_prefix "[#{s/C-/Ctrl+/:prefix}] %:Split left/right |:Split top/bottom Arrows:Move z:Zoom [:Copy d:Detach"
# 2. Copy mode (F7). byobu uses vi keys
set -g @byobu_hint_copy "[Copy mode] Arrows/PgUp:Scroll Space:Select v:Rectangle Enter:Copy /:Search q:Quit (paste: #{s/C-/Ctrl+/:prefix} ])"
# 3. Typing into ALL panes (Alt+F9). Easy to trigger by accident, so make it loud
set -g @byobu_hint_sync "#[fg=colour231,bg=colour160,bold] WARNING: typing goes to ALL panes  Alt+F9:Turn off "
# 4. Zoomed (Shift+F11)
set -g @byobu_hint_zoom "[Zoomed] Shift+F11:Unzoom"
# 5. Several panes in the window
set -g @byobu_hint_panes "Shift+Arrows:Move #{s/C-/Ctrl+/:prefix} then Ctrl+Arrows:Resize Shift+F11:Zoom Ctrl+F6:Close"
# 6. A single pane (default)
set -g @byobu_hint_single "Ctrl+F2:Split left/right Shift+F2:Split top/bottom F2:New window"

# ---- Selection logic ----
# Each text is expanded with #{E:...}, so commas inside a text cannot break the conditional.
set -g @byobu_hint "#{?#{@byobu_hint_enabled},#{E:@byobu_hint_style}#{?client_prefix,#{E:@byobu_hint_prefix},#{?pane_in_mode,#{E:@byobu_hint_copy},#{?synchronize-panes,#{E:@byobu_hint_sync},#{?window_zoomed_flag,#{E:@byobu_hint_zoom},#{?#{>:#{window_panes},1},#{E:@byobu_hint_panes},#{E:@byobu_hint_single}}}}}}#[default] ,}"

# ---- Prepend to byobu's status-right ----
# byobu resets status-right to its default on every F5 before re-reading this file,
# so the hint is prepended exactly once. The check guards against a manual double source.
if-shell -F "#{m:*@byobu_hint*,#{status-right}}" "" "set -gF status-right '##{E:@byobu_hint}#{status-right}'"

# ---- Toggle the hint on/off: prefix + H ----
bind-key H set -gF @byobu_hint_enabled "#{?#{@byobu_hint_enabled},0,1}" \; refresh-client -S
