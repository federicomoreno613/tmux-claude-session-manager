#!/usr/bin/env bash
# Record a Codex/Claude session state on its tmux session for the picker.
# Usage:
#   state.sh working|waiting|idle              # infer tool from session name
#   state.sh codex|claude working|waiting|idle # explicit tool
# Hooks inherit the agent process environment, so $TMUX_PANE is set whenever the
# agent runs inside tmux. Outside tmux this is a no-op.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ -z "${TMUX_PANE:-}" ] && exit 0

if [[ "${1:-}" == "codex" || "${1:-}" == "claude" ]]; then
  tool="$1"
  state="${2:-idle}"
else
  state="${1:-idle}"
  session_for_tool=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null || true)
  tool=$(session_tool "$session_for_tool")
fi

case "$state" in
  working|waiting|idle) ;;
  *) state="idle" ;;
esac

session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
[ -z "$session" ] && exit 0

now="$(date +%s)"

# Edge-triggered desktop notification: fire once on the transition INTO waiting.
# Read the previous state BEFORE overwriting so repeated 'waiting' writes (hook
# re-fires) do not re-notify. Gated by @ai_notify (default on).
prev="$(tmux show-options -qv -t "$session" @ai_state 2>/dev/null)"
if [ "$state" = "waiting" ] && [ "$prev" != "waiting" ]; then
  if [ "$(get_tmux_option @ai_notify 'on')" = "on" ]; then
    path="$(tmux display-message -p -t "$session" '#{pane_current_path}' 2>/dev/null)"
    "$DIR/notify.sh" "AI · necesita input" "$tool · ${path/#$HOME/~}" >/dev/null 2>&1 &
  fi
fi

# Generic options used by this fork.
tmux set-option -t "$session" @ai_tool "$tool"
tmux set-option -t "$session" @ai_state "$state"
tmux set-option -t "$session" @ai_state_at "$now"

# Tool-specific options preserve compatibility and make manual introspection easy.
tmux set-option -t "$session" "@${tool}_state" "$state"
tmux set-option -t "$session" "@${tool}_state_at" "$now"
exit 0
