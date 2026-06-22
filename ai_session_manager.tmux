#!/usr/bin/env bash
# tmux-ai-session-manager
#
# List, monitor status, and jump across nested Codex CLI and Claude Code
# sessions from a single popup. Based on craftzdog/tmux-claude-session-manager.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

codex_launch_key="$(get_tmux_option @codex_launch_key 'x')"
claude_launch_key="$(get_tmux_option @claude_launch_key 'c')"
list_key="$(get_tmux_option @ai_list_key 'u')"

# Backward-compatible alias for people who still set the original option.
legacy_list_key="$(get_tmux_option @claude_list_key '')"
[ -n "$legacy_list_key" ] && list_key="$legacy_list_key"

# Launch (or re-attach to) an AI session for the current pane directory.
tmux bind-key "$codex_launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh codex '#{pane_current_path}' '#{window_id}'"

tmux bind-key "$claude_launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh claude '#{pane_current_path}' '#{window_id}'"

# Open the unified session picker. When pressed from inside a managed popup,
# list.sh closes that popup first so the picker opens full-size on the host.
tmux bind-key "$list_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{client_name}'"
