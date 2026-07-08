#!/usr/bin/env bash
# Rich preview for the project navigator (prefix p). Shows the project path,
# its generated local status (when cached), priority/score/note/Next Step and
# recent memory (from the cached digest), then the live session screen if one is running.
# Args: <name> <session> <path>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

name="${1:-}"
session="${2:-}"
path="${3:-}"

[ -n "$path" ] && printf '\033[1m%s\033[0m\n' "$path"

status="$(python3 "$DIR/status.py" --detail "$name" 2>/dev/null || true)"
if [ -n "$status" ]; then
  printf '\033[1mresumen IA local\033[0m\n%s\n' "$status"
else
  python3 "$DIR/status.py" --kick "$name" >/dev/null 2>&1 || true
  printf '\033[2m(resumen IA local pendiente; se refresca async si está viejo)\033[0m\n'
fi

printf '\033[2m%s\033[0m\n' "────────────────────────────"
detail="$(python3 "$DIR/digest.py" --detail "$name" 2>/dev/null)"
[ -n "$detail" ] && printf '%s\n' "$detail"
printf '\033[2m%s\033[0m\n' "────────────────────────────"

if [ -n "$session" ]; then
  tmux capture-pane -ept "$session" 2>/dev/null
else
  printf '\033[2m(sin sesión viva · enter abre terminal · ctrl-f abre Hermes en el proyecto)\033[0m\n'
fi
