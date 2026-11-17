# byobu-keyhints v0.1.0
# Entry point. install.sh makes byobu's .tmux.conf source this file.
# Under tpm, byobu-keyhints.tmux sources it. Keep this file non-executable:
# tpm tries to execute every *.tmux in this directory (tests/audit.sh checks the mode).
# Paths below use #{d:current_file}, so moving the folder needs no edits here
# (install.sh's absolute path in .tmux.conf is the only thing to redo).

# Optional: fix for "11;rgb:..." junk at the prompt (see conf/fix-osc-garbage.tmux).
# Off unless `set -g @byobu_fix_osc_garbage 1` appears before this file is sourced.
# When off, an empty file (/dev/null) is sourced instead.
source-file -F "#{?#{@byobu_fix_osc_garbage},#{d:current_file}/conf/fix-osc-garbage.tmux,/dev/null}"

source-file -F "#{d:current_file}/conf/hints.tmux"
