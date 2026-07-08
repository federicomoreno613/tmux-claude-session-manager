#!/usr/bin/env bash
# prefix p -> ctrl-f: abrir (o reusar) una ventana Hermes dedicada al proyecto
# seleccionado, con el directorio del proyecto como cwd. Hermes es ahora el
# orquestador/copiloto (reemplaza el viejo dispatch a FirstMate). Idempotente por
# proyecto: si ya hay una ventana `hermes:<proyecto>`, salta a ella.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

name="${1:-}"
path="${2:-}"
[ -n "$name" ] || exit 0
case "$path" in "~"*) path="$HOME${path#\~}" ;; esac
[ -d "$path" ] || { tmux display-message "No existe: $path"; exit 0; }

cmd="$(get_tmux_option @ai_hermes_command 'hermes')"
win_name="hermes:$name"

# Reusar la ventana Hermes de este proyecto si ya existe (sin duplicar).
win="$(tmux list-windows -a -F '#{window_id}|#{window_name}' 2>/dev/null \
  | awk -F'|' -v n="$win_name" '$2==n{print $1; exit}')"
if [ -n "$win" ]; then
  sess="$(tmux display-message -p -t "$win" '#{session_name}' 2>/dev/null || true)"
  [ -n "$sess" ] && tmux switch-client -t "$sess" 2>/dev/null || true
  tmux select-window -t "$win" 2>/dev/null || true
  exit 0
fi

if ! command -v hermes >/dev/null 2>&1; then
  tmux display-message "Hermes no está en PATH (~/.local/bin/hermes)"
  exit 0
fi

# Nueva ventana en el dir del proyecto → Hermes arranca con ese contexto/cwd.
wid="$(tmux new-window -P -F '#{window_id}' -n "$win_name" -c "$path" "$cmd")"
[ -n "$wid" ] && tmux set-option -w -t "$wid" @ai_project "$path"
