# shellcheck shell=bash
# Shared by install.sh and uninstall.sh (sourced, not run).

# Same lookup order as byobu: ~/.byobu if it exists, otherwise the XDG location.
config_dir() {
  if [ -n "${BYOBU_CONFIG_DIR:-}" ]; then echo "$BYOBU_CONFIG_DIR"
  elif [ -d "$HOME/.byobu" ]; then echo "$HOME/.byobu"
  else echo "${XDG_CONFIG_HOME:-$HOME/.config}/byobu"
  fi
}

# byobu runs `tmux $(cat windows.tmux)`: the file is split on whitespace into tmux's
# command line, so it must be ONE line with no comments and no quotes. That is also why
# the home directory is written as an absolute path (tmux does not expand ~ there), and
# why uninstall.sh recognises our file by exact content instead of by a marker comment.
# Panes: 0 top-left, 1 bottom-left, 2 top-right, 3 bottom-right. Focus ends on pane 0.
layout_line() {
  local c="-c $HOME"
  echo "new-session $c ; split-window -h $c ; split-window -v $c ; select-pane -t 0 ; split-window -v $c ; select-pane -t 0"
}
