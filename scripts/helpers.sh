#!/usr/bin/env bash
# Shared helpers for tmux-ai-session-manager.

# get_tmux_option <option-name> <default>
# Echoes the global tmux option value, or the default when unset/empty.
get_tmux_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

# session_hash <string>
# Short, stable, portable 8-char hash for deriving a session name from a path.
session_hash() {
  local out
  if command -v md5sum >/dev/null 2>&1; then
    out="$(printf '%s\n' "$1" | md5sum)"
  elif command -v md5 >/dev/null 2>&1; then
    out="$(printf '%s\n' "$1" | md5 -q)"
  else
    out="$(printf '%s\n' "$1" | shasum)"
  fi
  printf '%s' "${out%% *}" | cut -c1-8
}

codex_prefix() { get_tmux_option @codex_session_prefix 'codex-'; }
claude_prefix() { get_tmux_option @claude_session_prefix 'claude-'; }

is_managed_session_name() {
  local name="${1:-}"
  local cp xp
  cp="$(codex_prefix)"
  xp="$(claude_prefix)"
  [[ "$name" == "$cp"* || "$name" == "$xp"* ]]
}

session_tool() {
  local name="${1:-}"
  local explicit cp xp
  explicit="$(tmux show-options -qv -t "$name" @ai_tool 2>/dev/null || true)"
  if [[ "$explicit" == "codex" || "$explicit" == "claude" ]]; then
    printf '%s' "$explicit"
    return 0
  fi
  cp="$(codex_prefix)"
  xp="$(claude_prefix)"
  if [[ "$name" == "$cp"* ]]; then
    printf '%s' codex
  elif [[ "$name" == "$xp"* ]]; then
    printf '%s' claude
  else
    printf '%s' ai
  fi
}
