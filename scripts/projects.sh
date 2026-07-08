#!/usr/bin/env bash
# Project navigator / hub (prefix p): fuzzy-pick a project by name (or path),
# ranked by priority, decorated with the live state of its AI session (if any).
#   - the list is ranked by the priorities digest (most important first), so
#     navigating it IS reading the priorities;
#   - a leading ● shows the session state for that project (waiting/working/
#     idle/live), blank if no session is running;
#   - enter JUMPS to the project's session if one exists, else opens a terminal;
#   - ctrl-t cycles P1/P2/P3, ctrl-o writes a forward-looking note (HIL), and
#     ctrl-f opens Hermes (tu orquestador/copiloto) en el directorio del proyecto
#     — reemplaza el viejo dispatch a FirstMate. Type to filter.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
self="${BASH_SOURCE[0]}"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"
# shellcheck source=rows.sh
. "$DIR/rows.sh"

# Emit annotated rows: name \t path \t session \t display. `display` is the
# aligned pretty column prefixed with a colored state dot. `session` is the live
# tmux session for that project dir (empty if none) so enter can jump to it.
emit_annotated() {
  local rows states
  rows="$(python3 "$DIR/projects.py" 2>/dev/null)"        # name path count pretty
  [ -z "$rows" ] && return 0
  states="$(emit_rows 2>/dev/null)"                        # rank session tool icon age path
  awk -F'\t' -v OFS='\t' -v home="$HOME" '
    function abspath(p) { return (substr(p,1,1)=="~") ? home substr(p,2) : p }
    FNR==NR {                       # states: keep lowest-rank (most urgent) per path
      k=abspath($6)
      if (!(k in r) || $1 < r[k]) { r[k]=$1; s[k]=$2 }
      next
    }
    {                               # project rows: name(1) path(2) count(3) pretty(4)
      k=abspath($2)
      rank = (k in r) ? r[k] : -1
      sess = (k in s) ? s[k] : ""
      if      (rank==0) dot="\033[33m●\033[0m"   # waiting - needs you
      else if (rank==1) dot="\033[32m●\033[0m"   # idle - your turn
      else if (rank==2) dot="\033[90m●\033[0m"   # unknown
      else if (rank==3) dot="\033[31m●\033[0m"   # working
      else if (rank==4) dot="\033[36m●\033[0m"   # live (unmanaged)
      else              dot=" "                    # no session
      print $1, $2, sess, dot " " $4
    }
  ' <(printf '%s\n' "$states") <(printf '%s\n' "$rows")
}

# Reload entry point (called by fzf binds so the list re-ranks/re-decorates live).
[ "${1:-}" = "--rows" ] && { emit_annotated; exit 0; }

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-ai-session-manager: fzf is required"
  exit 0
fi

annotated="$(emit_annotated)"
if [ -z "$annotated" ]; then
  tmux display-message "No hay proyectos conocidos todavía (engram sin sesiones)"
  exit 0
fi

# ctrl-f abre Hermes (orquestador/copiloto) en el proyecto — reemplaza el viejo
# dispatch a FirstMate. Ver hermes-project.sh.
header='PRIORIDADES (mayor→menor) · ● = sesión viva (🟡 te espera · 🔴 trabajando · 🟢 listo · 🔵 a mano)'
footer='enter: saltar/abrir · ctrl-f: Hermes (etapas) · ctrl-e: VS Code · ctrl-t: prioridad · ctrl-o: nota · shift-↑↓: scroll · esc: salir'
# `test -n {1}` makes the bind a no-op on freshness separator rows (empty name).
pin_bind="ctrl-t:execute-silent(test -n {1} && python3 $DIR/digest.py --cycle-prio {1})+reload($self --rows)"
note_bind="ctrl-o:execute($DIR/note-edit.sh {1})+reload($self --rows)"
hermes_bind="ctrl-f:become($DIR/hermes-project.sh {1} {2})"
# ctrl-e: abrir el proyecto seleccionado en VS Code (sin cerrar el navegador).
editor_bind="ctrl-e:execute-silent($DIR/open-editor.sh {2})"
# Read the full summary: scroll the preview (shift-↑/↓) and toggle a tall preview
# (ctrl-y) when a status/Next Step is long.
scroll_bind="shift-up:preview-up,shift-down:preview-down,ctrl-y:change-preview-window(down,80%|down,45%)"

# Display the decorated column (field 4); search over name + path (fields 1,2).
# Preview passes the session (field 3) so it shows the live screen when present.
sel="$(printf '%s\n' "$annotated" | fzf --ansi --delimiter='\t' \
  --with-nth=4 --nth=1,2 \
  --reverse --cycle --header="$header" --footer="$footer" \
  --bind="$pin_bind" --bind="$note_bind" --bind="$hermes_bind" --bind="$editor_bind" --bind="$scroll_bind" \
  --preview="$DIR/preview-project.sh {1} {3} {2}" --preview-window='down,45%,wrap')"

[ -z "$sel" ] && exit 0
path="$(printf '%s' "$sel" | cut -f2)"
session="$(printf '%s' "$sel" | cut -f3)"
name="$(printf '%s' "$sel" | cut -f1)"
# A freshness separator row has no path: selecting it is a no-op.
[ -z "$path" ] && exit 0
case "$path" in "~"*) path="$HOME${path#\~}" ;; esac

# Smart enter (sin duplicados): 1) salta a la sesión de agente viva si existe;
# 2) si no, reusa una ventana que ya esté en ese path; 3) si no, abre una nueva.
if [ -n "$session" ] && tmux has-session -t "$session" 2>/dev/null; then
  exec tmux attach-session -t "$session"
fi
[ -d "$path" ] || { tmux display-message "No existe: $path"; exit 0; }

# Reusar una ventana existente cuyo pane activo ya esté en $path (mata las
# "pestañas repetidas con la misma pantalla"). Prioriza la marcada @ai_project.
existing="$(tmux list-panes -a \
  -F '#{pane_active}|#{session_name}:#{window_index}|#{pane_current_path}|#{@ai_project}' 2>/dev/null \
  | awk -F'|' -v p="$path" '$1==1 && ($4==p || $3==p){print $2; exit}')"
if [ -n "$existing" ]; then
  tmux switch-client -t "$existing" 2>/dev/null || tmux select-window -t "$existing"
  exit 0
fi
wid="$(tmux new-window -P -F '#{window_id}' -n "$name" -c "$path")"
[ -n "$wid" ] && tmux set-option -w -t "$wid" @ai_project "$path"
