#!/usr/bin/env bash
# Interactive picker for running Codex and Claude sessions.
#   picker.sh           fzf picker; enter jumps/resumes the selected session.
#   picker.sh --list    print rows only (used by fzf ctrl-x reload).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

emit_rows() {
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
    # rank \t session \t tool \t icon \t age \t path  (rank/session hidden via --with-nth)
    printf '%s\t%s\t%-6s\t%s\t%5s\t%s\n' "$rank" "$s" "$tool" "$icon" "$ago" "${path/#$HOME/~}"
  done | sort -t$'\t' -k1,1n -k5,5n
}

[ "${1:-}" = '--list' ] && {
  emit_rows
  exit 0
}

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-ai-session-manager: fzf is required for the picker"
  exit 0
fi

self="${BASH_SOURCE[0]}"
export FZF_DEFAULT_OPTS=''
sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=3,4,5,6 \
  --reverse --cycle --header='AI sessions · enter: jump · ctrl-x: kill' \
  --preview="tmux capture-pane -ept {2}" --preview-window='right,62%,wrap' \
  --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload($self --list)")

[ -z "$sel" ] && exit 0
target=$(printf '%s' "$sel" | cut -f2)

origin=$(tmux show-options -qv -t "$target" @ai_origin 2>/dev/null)
[ -z "$origin" ] && origin=$(tmux show-options -qv -t "$target" @claude_origin 2>/dev/null)
parent=$(tmux show-options -gqv @ai_parent 2>/dev/null)
[ -z "$parent" ] && parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux attach-session -t "$target"
