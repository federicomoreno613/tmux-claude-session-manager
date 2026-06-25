#!/usr/bin/env bash
# Open/reuse the single FirstMate supervisor and inject the selected project
# context from the project navigator (prefix p -> ctrl-f). With --restart, kill
# the existing FirstMate session first so it comes back with a fresh context
# window (durable state lives in engram + firstmate/data/, so nothing is lost).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

restart=0
dispatch=0
if [ "${1:-}" = "--restart" ]; then restart=1; shift; fi
if [ "${1:-}" = "--dispatch" ]; then dispatch=1; shift; fi
name="${1:-}"
path="${2:-}"
[ -n "$name" ] || exit 0
case "$path" in "~"*) path="$HOME${path#\~}" ;; esac

# Dispatch mode (ctrl-e "encargar"): prompt for a concrete task + scope, then
# build a structured authorization envelope instead of the read-only context.
# We leave the envelope pasted but DO NOT send Enter, so Federico reviews and
# confirms — avoids racing FirstMate mid-turn and keeps a human checkpoint.
task=""
scope="scout"
if [ "$dispatch" -eq 1 ]; then
  printf '\n¿Qué encargás en %s? (enter vacío = cancelar): ' "$name" > /dev/tty
  IFS= read -r task < /dev/tty
  [ -n "$task" ] || exit 0
  printf 'scope [scout]/ship: ' > /dev/tty
  IFS= read -r scope_in < /dev/tty
  case "$scope_in" in ship|SHIP|s) scope="ship" ;; *) scope="scout" ;; esac
fi

fmpath="$(get_tmux_option @ai_firstmate_path "$HOME/firstmate")"
fmcmd="$(get_tmux_option @claude_command 'claude')"
fmsess="$(claude_prefix)$(session_hash "$fmpath")"
buf="ai-firstmate-context"

[ "$restart" -eq 1 ] && tmux kill-session -t "$fmsess" 2>/dev/null || true

created=0
if ! tmux has-session -t "$fmsess" 2>/dev/null; then
  tmux new-session -d -s "$fmsess" -c "$fmpath" "$fmcmd"
  created=1
fi

if [ "$dispatch" -eq 1 ]; then
  ctx="$(printf '%s' "$task" | python3 "$DIR/status.py" --dispatch "$scope" "$name" "$path" 2>/dev/null)"
else
  ctx="$(python3 "$DIR/status.py" --context "$name" "$path" 2>/dev/null)"
fi
if [ -z "$ctx" ]; then
  ctx="Contexto seleccionado desde cockpit.\n\nProyecto: $name\nPath: $path\n\nUsá este contexto para orientar la conversación."
fi

# On a cold start, wait until Claude/FirstMate has actually drawn its UI before
# pasting. A fixed short sleep races the TUI boot, so the paste and Enter get
# lost — which looked like "FirstMate didn't respond / dropped me to a shell".
# Poll the pane until it is non-empty (bounded), then a small settle margin.
if [ "$created" -eq 1 ]; then
  printf 'Abriendo FirstMate… (esperando que arranque)\n' > /dev/tty 2>/dev/null || true
  ready_to="$(get_tmux_option @ai_firstmate_ready_timeout '15')"
  i=0
  while [ "$i" -lt "$((ready_to * 2))" ]; do
    [ -n "$(tmux capture-pane -p -t "$fmsess" 2>/dev/null | tr -d '[:space:]')" ] && break
    sleep 0.5
    i=$((i + 1))
  done
  sleep "$(get_tmux_option @ai_firstmate_inject_delay '1')"
fi

printf '%s\n' "$ctx" | tmux load-buffer -b "$buf" -
tmux paste-buffer -t "$fmsess" -b "$buf"
tmux delete-buffer -b "$buf" 2>/dev/null || true
# Dispatch leaves the envelope pasted but unsent: Federico reviews and presses
# Enter himself. Read-only context (ctrl-f) auto-sends as before.
[ "$dispatch" -eq 1 ] || tmux send-keys -t "$fmsess" Enter

# Land the user in FirstMate. This runs inside a tmux popup, where attach-session
# is refused as nested and would drop the user to a bare shell — switch-client is
# the correct primitive there. Fall back to attach only when not in a client.
tmux has-session -t "$fmsess" 2>/dev/null || { tmux display-message "FirstMate no disponible"; exit 1; }
if tmux switch-client -t "$fmsess" 2>/dev/null; then
  exit 0
fi
exec tmux attach-session -t "$fmsess"
