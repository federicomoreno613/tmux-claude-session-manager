#!/usr/bin/env bash
# Lanzar un agente experto (guardado en ~/.claude/agents/<slug>.md) a trabajar de
# forma AUTÓNOMA en un proyecto, en su propia sesión tmux. Aparece en Ctrl-b p / g
# como una sesión managed (prefijo claude-), y sobrevive al detach.
# Uso: expert-dispatch.sh <slug> <project_path> <task>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

slug="${1:-}"; path="${2:-}"; task="${3:-}"
[ -n "$slug" ] && [ -n "$path" ] && [ -n "$task" ] || { echo "uso: expert-dispatch.sh <slug> <path> <task>"; exit 2; }
case "$path" in "~"*) path="$HOME${path#\~}" ;; esac
[ -d "$path" ] || { echo "no existe el path: $path"; exit 1; }

agent_file="$HOME/.claude/agents/${slug}.md"
[ -f "$agent_file" ] || { echo "falta el agente ~/.claude/agents/${slug}.md — crealo antes de despachar"; exit 1; }

cmd="$(get_tmux_option @claude_command 'claude')"
session="$(claude_prefix)${slug}-$(session_hash "$path")"

# Idempotente: si ya hay una sesión de este experto en este proyecto, saltá a ella.
if tmux has-session -t "$session" 2>/dev/null; then
  tmux display-message "Ya hay una sesión de '$slug' en $(basename "$path") — Ctrl-b u para verla"
  exit 0
fi

seed="Adoptá completamente el rol del agente definido en ~/.claude/agents/${slug}.md (leé ese archivo y comportate como ese experto).

Tarea: ${task}

GUARDRAILS (importante): trabajá de forma autónoma, pero PARÁ y pedí confirmación explícita antes de CUALQUIER acción irreversible o de producción — deploys a prod, crear/borrar recursos cloud, gastos, o cambios en infra/datos live. Preferí primero un plan o un dry-run. Cuando termines, o cuando necesites una decisión mía, dejá la sesión esperando input (no cierres)."

tmux new-session -d -s "$session" -c "$path" "$cmd"
tmux set-option -t "$session" @ai_tool claude
tmux set-option -t "$session" @ai_project "$path"

# Esperar a que el TUI de Claude dibuje antes de inyectar (un sleep fijo pierde el
# mensaje si el arranque es lento). Poll acotado + margen de asentamiento.
i=0
while [ "$i" -lt 30 ]; do
  [ -n "$(tmux capture-pane -p -t "$session" 2>/dev/null | tr -d '[:space:]')" ] && break
  sleep 0.5; i=$((i + 1))
done
sleep 1
tmux send-keys -t "$session" -l "$seed"
tmux send-keys -t "$session" Enter

tmux display-message "Experto '$slug' lanzado en $(basename "$path"). Miralo con Ctrl-b p / Ctrl-b g (te avisa cuando necesita input)."
