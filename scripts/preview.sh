#!/usr/bin/env bash
# Picker preview: a short context header (project + engram summary + badges)
# followed by the live screen of the session. Args: <session> <path>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

session="${1:-}"
path="${2:-}"

if [ -n "$path" ]; then
  printf '\033[1m%s\033[0m\n' "$path"
  line="$(python3 "$DIR/context.py" --line "$path" 2>/dev/null)"
  [ -n "$line" ] && printf '\033[2m%s\033[0m\n' "$line"
  printf '\033[2m%s\033[0m\n' "────────────────────────────"
fi

[ -n "$session" ] && tmux capture-pane -ept "$session" 2>/dev/null
