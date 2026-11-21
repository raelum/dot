#!/usr/bin/env python3
"""
Tmux Tap-to-Cursor Navigation:
Translates a mouse tap on the prompt area into atomic Left/Right/Up/Down arrow keys.
Protects terminal output by ignoring taps outside prompt bounds.
"""
import re
import subprocess
import sys
import unicodedata

# Full-width horizontal rule used by TUI prompt boxes (e.g. agy)
DIVIDER_RE = re.compile(r'^─{20,}$')
# Standard shell prompt at start of line (e.g. "~/code $ ", "$ ", "> ", "❯ ")
SHELL_PROMPT_RE = re.compile(r'^[^\s]*\s*[$%#❯>](?:\s|$)')

def is_divider(line):
    # Real TUI dividers start at column 0 (no leading prompt indentation)
    return bool(DIVIDER_RE.match(line.rstrip()))

def col_to_char_idx(line, target_col):
    """Maps a terminal column coordinate to a character index (clamped to text end)."""
    trimmed = line.rstrip()
    col = 0
    for idx, ch in enumerate(trimmed):
        if col >= target_col:
            return idx
        if unicodedata.combining(ch):
            continue
        col += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return len(trimmed)

def detect_prompt_bounds(lines, cursor_y):
    """
    Detects the prompt region bounded around cursor_y.
    Returns (start_y, end_y).
    """
    if cursor_y < 0 or cursor_y >= len(lines):
        return None

    # 1. Boxed TUI prompt (e.g. agy): strictly enclosed by full-width dividers
    top_div = next((y for y in range(cursor_y - 1, -1, -1) if is_divider(lines[y])), None)
    bot_div = next(
        (y for y in range(cursor_y + 1, len(lines)) if is_divider(lines[y]) or "esc to cancel" in lines[y]),
        None,
    )
    if top_div is not None and bot_div is not None and top_div + 1 <= cursor_y <= bot_div - 1:
        return top_div + 1, bot_div - 1

    # 2. Fallback: standard shell prompt (bash/zsh)
    start_y = None
    for y in range(cursor_y, -1, -1):
        line = lines[y]
        if y < cursor_y and is_divider(line):
            break
        if SHELL_PROMPT_RE.match(line):
            start_y = y
            break

    if start_y is None:
        return None

    end_y = cursor_y
    while end_y + 1 < len(lines):
        next_line = lines[end_y + 1]
        if not next_line.strip() or is_divider(next_line) or "esc to cancel" in next_line:
            break
        end_y += 1

    return start_y, end_y

def calculate_arrow_keys(lines, cursor_x, cursor_y, mouse_x, mouse_y):
    """
    Calculates arrow key sequence for a tap at (mouse_x, mouse_y).
    Returns list of arrow keys or None if outside prompt bounds.
    """
    bounds = detect_prompt_bounds(lines, cursor_y)
    if not bounds:
        return None

    start_y, end_y = bounds

    # Ignore taps outside prompt bounds (protect scrollback & status bars)
    if mouse_y < start_y or mouse_y > end_y:
        return None

    # Convert display columns to character indices (handles clamping + wide CJK/emoji)
    tapped_line = lines[mouse_y]
    target_idx = col_to_char_idx(tapped_line, mouse_x)
    cursor_idx = col_to_char_idx(tapped_line, cursor_x)

    # 1. Vertical adjustment
    delta_y = mouse_y - cursor_y
    arrow_keys = ["Down" if delta_y > 0 else "Up"] * abs(delta_y)

    # 2. Horizontal adjustment
    delta_x = target_idx - cursor_idx
    arrow_keys += ["Right" if delta_x > 0 else "Left"] * abs(delta_x)

    return arrow_keys

def main():
    if len(sys.argv) < 6:
        sys.exit(0)

    pane_id = sys.argv[1]
    mouse_x = int(sys.argv[2])
    mouse_y = int(sys.argv[3])
    cursor_x = int(sys.argv[4])
    cursor_y = int(sys.argv[5])

    # Fetch visible screen buffer from the tapped pane
    try:
        raw_output = subprocess.check_output(
            ["tmux", "capture-pane", "-p", "-t", pane_id],
            text=True
        )
    except Exception:
        sys.exit(0)

    # Compute arrow keys to reach tap location (exits if tap is outside prompt)
    lines = raw_output.splitlines()
    arrow_keys = calculate_arrow_keys(lines, cursor_x, cursor_y, mouse_x, mouse_y)
    if not arrow_keys:
        sys.exit(0)

    # Send arrow keys to reposition cursor
    cmd = ["tmux", "send-keys", "-t", pane_id] + arrow_keys
    subprocess.run(cmd)

if __name__ == "__main__":
    main()
