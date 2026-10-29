#!/bin/sh

MODE=$(tmux show-option -gv window-size 2>/dev/null)
CLIENT_W=$(tmux display-message -p '#{client_width}' 2>/dev/null)
[ -z "$CLIENT_W" ] || [ "$CLIENT_W" -le 0 ] 2>/dev/null && CLIENT_W=100

if [ "$MODE" = "manual" ]; then
    # Disable padding: restore auto-sizing and snap windows to full screen
    tmux set-option -g window-size latest
    for win in $(tmux list-windows -a -F '#{window_id}'); do
        tmux resize-window -t "$win" -A 2>/dev/null || true
        tmux set-option -u -t "$win" window-size 2>/dev/null || true
    done
    tmux display-message "Screen padding: OFF (Full width)"
else
    # Enable padding: snap height to screen (-A) and pad width (-x)
    TARGET_W=$(( CLIENT_W - 31 ))
    [ "$TARGET_W" -lt 40 ] && TARGET_W="$CLIENT_W"

    tmux set-option -g window-size manual
    for win in $(tmux list-windows -a -F '#{window_id}'); do
        tmux resize-window -t "$win" -A \; resize-window -t "$win" -x "$TARGET_W" 2>/dev/null || true
    done
    tmux display-message "Screen padding: ON (${TARGET_W} cols, dots on right)"
fi
