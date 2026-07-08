#!/usr/bin/env bash
# Shared row emitter for the AI session manager.
# Sourced by picker.sh, dashboard.py (via subprocess), status.sh and
# jump-waiting.sh so session enumeration, state ranking and colors live in one
# place.
#
# emit_rows prints one tab-separated line per managed session:
#   rank \t session \t tool \t icon \t age \t path
# pre-sorted by rank (waiting=0, idle=1, ?=2, working=3) then by age.

# Requires helpers.sh to be sourced first (is_managed_session_name, session_tool).

# Managed sessions (launched with prefix c/x): precise state from hooks.
_emit_managed() {
  local now s state at path icon rank ago tool
  now=$(date +%s)
  tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do
    is_managed_session_name "$s" || continue
    tool=$(session_tool "$s")
    state=$(tmux show-options -qv -t "$s" @ai_state 2>/dev/null)
    [ -z "$state" ] && state=$(tmux show-options -qv -t "$s" "@${tool}_state" 2>/dev/null)
    at=$(tmux show-options -qv -t "$s" @ai_state_at 2>/dev/null)
    [ -z "$at" ] && at=$(tmux show-options -qv -t "$s" "@${tool}_state_at" 2>/dev/null)
    path=$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)
    case "$state" in
      waiting) icon=$'\033[33m●\033[0m waiting' rank=0 ;; # yellow - needs input
      idle) icon=$'\033[32m●\033[0m idle   ' rank=1 ;;    # green  - done, your turn
      working) icon=$'\033[31m●\033[0m working' rank=3 ;; # red    - busy, leave it
      *) icon=$'\033[90m●\033[0m   ?    ' rank=2 ;;       # grey   - unknown/no hook yet
    esac
    if [ -n "$at" ]; then ago="$(((now - at) / 60))m"; else ago='-'; fi
    # rank \t session \t tool \t icon \t age \t path
    printf '%s\t%s\t%-6s\t%s\t%5s\t%s\n' "$rank" "$s" "$tool" "$icon" "$ago" "${path/#$HOME/~}"
  done
}

# Unmanaged agents: claude/codex running directly in any tmux pane (not started
# with prefix c/x). No hook state, so they show as "live" (rank 4, sorted last).
# Toggle with @ai_detect_unmanaged (default on); commands via @ai_detect_commands.
_emit_unmanaged() {
  [ "$(get_tmux_option @ai_detect_unmanaged 'on')" = "on" ] || return 0
  local detect pid s cmd path icon c
  detect="$(get_tmux_option @ai_detect_commands 'claude codex hermes')"
  # Query one field per call (tmux -F mangles embedded tabs); join with printf.
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | while IFS= read -r pid; do
    s=$(tmux display-message -p -t "$pid" '#{session_name}' 2>/dev/null)
    is_managed_session_name "$s" && continue
    cmd=$(tmux display-message -p -t "$pid" '#{pane_current_command}' 2>/dev/null)
    for c in $detect; do
      if [ "$cmd" = "$c" ]; then
        path=$(tmux display-message -p -t "$pid" '#{pane_current_path}' 2>/dev/null)
        icon=$'\033[36m●\033[0m live   ' # cyan - running, no managed state
        printf '%s\t%s\t%-6s\t%s\t%5s\t%s\n' 4 "$s" "$c" "$icon" '-' "${path/#$HOME/~}"
        break
      fi
    done
  done
}

# Combined, sorted by rank then age. Single source of truth for all consumers.
emit_rows() {
  { _emit_managed; _emit_unmanaged; } | sort -t$'\t' -k1,1n -k5,5n
}
