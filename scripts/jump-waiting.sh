#!/usr/bin/env bash
# Jump straight to the next session that needs input (state == waiting),
# oldest first, without opening the picker. Bound to `prefix g` (Go).
# Falls back to a message when nothing is waiting.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"
# shellcheck source=rows.sh
. "$DIR/rows.sh"

# Don't open a nested popup from inside a managed session.
current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
if is_managed_session_name "$current_session"; then
  tmux display-message 'Ya estás dentro de una sesión AI'
  exit 0
fi

# emit_rows is pre-sorted: rank 0 (waiting) first, oldest first. Grab the first
# waiting row (rank field == 0).
target="$(emit_rows | awk -F'\t' '$1==0 {print $2; exit}')"

if [ -z "$target" ]; then
  tmux display-message 'No hay sesiones esperando input'
  exit 0
fi

# Record where we jumped from, so the picker can hop back later.
window="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
[ -n "$window" ] && tmux set-option -t "$target" @ai_origin "$window"

w="$(get_tmux_option @ai_popup_width "$(get_tmux_option @claude_popup_width '90%')")"
h="$(get_tmux_option @ai_popup_height "$(get_tmux_option @claude_popup_height '90%')")"
tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t '$target'"
