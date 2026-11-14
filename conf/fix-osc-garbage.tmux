# Optional fix for junk like "11;rgb:1717/1414/2121" showing up at the shell prompt.
#
# Why it happens:
#   When vim or the shell asks the terminal "what is your background color?"
#   (OSC 10/11), Windows Terminal answers "ESC ] 11;rgb:RRRR/GGGG/BBBB ESC \".
#   byobu's stock profile sets escape-time to 0. If the reply arrives split up
#   and late through WSL, tmux treats the lone ESC as a keypress, and the rest
#   ("11;rgb:...") leaks into the shell as ordinary typed characters.
#
# Why 50 ms:
#   Nobody types ESC and the next key within 50 ms, and vim's ESC delay is not
#   noticeable at that value. The split replies seen over WSL fit inside it.
#   If junk still appears, raise it to 100-300.
set -sg escape-time 50
