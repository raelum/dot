#!/usr/bin/env python3
"""
Tmux Tap-to-Cursor Navigation:
Translates a mouse tap on the prompt area into atomic Left/Right/Up/Down arrow keys.
Protects terminal output by ignoring taps outside prompt bounds.
"""
import re
import subprocess
import sys

def detect_prompt_bounds(lines, cursor_y):
    """
    Detects the prompt region bounded around cursor_y.
    Returns (start_y, end_y).
    """
    if cursor_y < 0 or cursor_y >= len(lines):
        return None

    # Scan upward from cursor_y to find prompt start
    start_y = None
    for y in range(cursor_y, max(-1, cursor_y - 20), -1):
        line = lines[y]
        if y < cursor_y and "─" in line:
            break
        if re.search(r'(^|\s*)([>❯$%#])\s', line):
            start_y = y
            break

    if start_y is None:
        return None

    # Scan downward from cursor_y to find prompt end
    end_y = cursor_y
    while end_y + 1 < len(lines):
        next_line = lines[end_y + 1]
        if "─" in next_line or "esc to cancel" in next_line:
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

    # Clamp both X coordinates to visible line length:
    # - clamped_mouse_x: snaps tap target to text end (ignores empty right margin)
    # - clamped_cursor_x: matches where terminal lands cursor after vertical move
    tapped_line = lines[mouse_y]
    line_content_end = len(tapped_line.rstrip())
    clamped_mouse_x = min(mouse_x, line_content_end)
    clamped_cursor_x = min(cursor_x, line_content_end)

    # 1. Vertical adjustment
    delta_y = mouse_y - cursor_y
    arrow_keys = ["Down" if delta_y > 0 else "Up"] * abs(delta_y)

    # 2. Horizontal adjustment
    delta_x = clamped_mouse_x - clamped_cursor_x
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
