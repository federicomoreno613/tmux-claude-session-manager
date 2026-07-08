#!/usr/bin/env bash
# prefix h: abrir (o reusar) una ventana tmux dedicada a Hermes, tu copiloto
# organizador. Idempotente — si ya hay una ventana 'hermes', salta a ella en vez
# de duplicarla, así la conversación persiste al hacer detach.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

name="$(get_tmux_option @ai_hermes_window 'hermes')"
cmd="$(get_tmux_option @ai_hermes_command 'hermes')"

# ¿Ya existe una ventana Hermes en cualquier sesión? Reusar (no duplicar).
win="$(tmux list-windows -a -F '#{window_id}|#{window_name}' 2>/dev/null \
  | awk -F'|' -v n="$name" '$2==n{print $1; exit}')"

if [ -n "$win" ]; then
  sess="$(tmux display-message -p -t "$win" '#{session_name}' 2>/dev/null || true)"
  [ -n "$sess" ] && tmux switch-client -t "$sess" 2>/dev/null || true
  tmux select-window -t "$win" 2>/dev/null || true
  exit 0
fi

if ! command -v hermes >/dev/null 2>&1; then
  tmux display-message "Hermes no está en PATH (esperado en ~/.local/bin/hermes)"
  exit 0
fi

tmux new-window -n "$name" "$cmd"
