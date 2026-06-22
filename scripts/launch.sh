#!/usr/bin/env bash
# Launch (or re-attach to) a Codex/Claude session for a directory, shown in a popup.
# Args: <tool> <dir> [origin-window-id]
# Backward compatibility: launch.sh <dir> [origin-window-id] launches Claude.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

if [[ "${1:-}" == "codex" || "${1:-}" == "claude" ]]; then
  tool="$1"
  path="${2:-$PWD}"
  window="${3:-}"
else
  tool="claude"
  path="${1:-$PWD}"
  window="${2:-}"
fi

case "$tool" in
  codex)
    prefix="$(get_tmux_option @codex_session_prefix 'codex-')"
    cmd="$(get_tmux_option @codex_command 'codex')"
    ;;
  claude)
    prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
    cmd="$(get_tmux_option @claude_command 'claude')"
    ;;
  *)
    tmux display-message "tmux-ai-session-manager: unknown tool '$tool'"
    exit 1
    ;;
esac

w="$(get_tmux_option @ai_popup_width "$(get_tmux_option @claude_popup_width '90%')")"
h="$(get_tmux_option @ai_popup_height "$(get_tmux_option @claude_popup_height '90%')")"
session="${prefix}$(session_hash "$path")"

current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
if is_managed_session_name "$current_session"; then
  tmux display-message 'AI session popup already open'
  exit 0
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  tmux new-session -d -s "$session" -c "$path" "$cmd"
  tmux set-option -t "$session" @ai_tool "$tool"
fi

# Record which window launched it, so the picker can jump back here later.
tmux set-option -t "$session" @ai_tool "$tool"
[ -n "$window" ] && tmux set-option -t "$session" @ai_origin "$window"
# Keep the original Claude option for compatibility with upstream picker behavior.
[ "$tool" = "claude" ] && [ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t '$session'"
