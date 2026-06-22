#!/usr/bin/env bash
# Open the unified Codex/Claude session picker in a popup.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

w="$(get_tmux_option @ai_popup_width "$(get_tmux_option @claude_popup_width '90%')")"
h="$(get_tmux_option @ai_popup_height "$(get_tmux_option @claude_popup_height '90%')")"

# The session of a client attached to a managed session — i.e. the popup we are
# inside, if any. Empty when invoked from a normal pane.
nested_session() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    while read -r _client sess; do
      if is_managed_session_name "$sess"; then
        printf '%s\n' "$sess"
        break
      fi
    done
}

# A client NOT attached to a managed session — the outer client that should host
# the picker popup.
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    while read -r client sess; do
      if ! is_managed_session_name "$sess"; then
        printf '%s\n' "$client"
        break
      fi
    done
}

# If we are inside a session popup, close it (detach its client).
sess="$(nested_session)"
if [ -n "$sess" ]; then
  tmux detach-client -s "$sess"
  for _ in $(seq 1 100); do
    [ -z "$(nested_session)" ] && break
    sleep 0.05
  done
fi

host="$(host_client)"
tmux set-option -g @ai_parent "$host"
# Preserve original option name for upstream compatibility.
tmux set-option -g @claude_parent "$host"

if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
