#!/usr/bin/env bash
# Open an "IDE" layout in a new tmux window:
#   ┌────────────────┬──────────┐
#   │  work (focus)  │          │
#   ├────────────────┤ cockpit  │
#   │   terminal     │          │
#   └────────────────┴──────────┘
# You work in the top-left pane (launch agents with prefix c/x, or just run
# claude/codex — both show in the cockpit). Bottom-left is a spare terminal.
# Usage: layout.sh [dir]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

path="${1:-$PWD}"
cockpit_size="$(get_tmux_option @ai_layout_cockpit_size '35%')"
term_size="$(get_tmux_option @ai_layout_term_size '25%')"
name="$(get_tmux_option @ai_layout_name 'cockpit')"

# Idempotent: if a layout window already exists in this session, jump to it
# instead of stacking another one. (prefix Space = "go to my workspace".)
# Select by window id (unambiguous even if names were duplicated before).
session="$(tmux display-message -p '#{session_name}' 2>/dev/null || true)"
if [ -n "$session" ]; then
  existing="$(tmux list-windows -t "$session" -F '#{window_id} #{window_name}' 2>/dev/null \
    | awk -v n="$name" '$2==n {print $1; exit}')"
  if [ -n "$existing" ]; then
    tmux select-window -t "$existing"
    exit 0
  fi
fi

# Work pane = a shell in the target dir, in a fresh window.
work="$(tmux new-window -P -F '#{pane_id}' -n "$name" -c "$path")" || exit 0

# Right column = cockpit dashboard.
tmux split-window -h -l "$cockpit_size" -t "$work" "exec $DIR/dashboard.py"

# Bottom-left = spare terminal (split the work pane vertically).
tmux split-window -v -l "$term_size" -t "$work" -c "$path"

# Land focus on the work pane (top-left).
tmux select-pane -t "$work"
