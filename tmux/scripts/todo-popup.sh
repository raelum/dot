#!/bin/sh

if [ "$(tmux show -gv window-size)" = "manual" ]; then
    # Calculate popup dimensions and coordinates if padding is toggled
    W=$(tmux display -p '#{window_width}')
    POPUP_W=$(( W * 85 / 100 ))
    POPUP_X=$(( (W - POPUP_W) / 2 ))
    POS_ARGS="-x $POPUP_X"
else
    # Otherwise calculate popup dimensions normally
    POPUP_W="80%"
    POS_ARGS=""
fi

tmux display-popup -E -w "$POPUP_W" -h 80% $POS_ARGS -d "$HOME/code" -T " todo " "TODO_POPUP=1 nvim ~/code/todo.md"
