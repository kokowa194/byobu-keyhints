#!/usr/bin/env bash
# Entry point for tpm (tmux plugin manager).
# tpm tries to execute every *.tmux file in the plugin's top directory. plugin.tmux is a
# tmux config, not a script, and is kept non-executable so that attempt fails harmlessly;
# this script hands it to tmux instead. The install.sh route sources plugin.tmux directly
# and never runs this file.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmux source-file "$CURRENT_DIR/plugin.tmux"
