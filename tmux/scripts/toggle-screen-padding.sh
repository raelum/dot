#!/bin/sh

MODE=$(tmux show-option -gv window-size 2>/dev/null)
CLIENT_W=$(tmux display-message -p '#{client_width}' 2>/dev/null)
CLIENT_H=$(tmux display-message -p '#{client_height}' 2>/dev/null)
[ -z "$CLIENT_W" ] || [ "$CLIENT_W" -le 0 ] 2>/dev/null && CLIENT_W=100
[ -z "$CLIENT_H" ] || [ "$CLIENT_H" -le 0 ] 2>/dev/null && CLIENT_H=18

STATUS=$(tmux show-option -gv status 2>/dev/null)
WIN_H="$CLIENT_H"
[ "$STATUS" != "off" ] && WIN_H=$(( CLIENT_H - 1 ))

if [ "$MODE" = "manual" ]; then
    # Restore auto-sizing and reset all windows to full client dimensions
    tmux set-option -g window-size latest
    tmux set-option -g default-size "${CLIENT_W}x${CLIENT_H}"
    for win in $(tmux list-windows -a -F '#{window_id}'); do
        tmux resize-window -t "$win" -x "$CLIENT_W" -y "$WIN_H" 2>/dev/null || true
        tmux set-option -u -t "$win" window-size 2>/dev/null || true
    done
    tmux display-message "Screen padding: OFF (Full width)"
else
    # Constrain width and set height to screen size across all windows and sessions
    TARGET_W=$(( CLIENT_W - 31 ))
    [ "$TARGET_W" -lt 40 ] && TARGET_W="$CLIENT_W"

    tmux set-option -g window-size manual
    tmux set-option -g default-size "${TARGET_W}x${CLIENT_H}"
    for win in $(tmux list-windows -a -F '#{window_id}'); do
        tmux resize-window -t "$win" -x "$TARGET_W" -y "$WIN_H" 2>/dev/null || true
    done
    tmux display-message "Screen padding: ON (${TARGET_W} cols, dots on right)"
fi
