#!/usr/bin/env bash
# Interactive picker for running Codex and Claude sessions.
#   picker.sh              fzf picker; enter jumps/resumes the selected session.
#   picker.sh --list       plain rows (used by the dashboard; fast, no context).
#   picker.sh --list-rich  rows + a description column (status + engram summary).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"
# shellcheck source=rows.sh
. "$DIR/rows.sh"

# Append a 7th field per row: a compact description (engram summary or badges).
# Kept out of --list so the 2s dashboard refresh stays cheap.
emit_rows_rich() {
  emit_rows | while IFS=$'\t' read -r rank session tool icon age path; do
    desc=$(python3 "$DIR/context.py" --row "$path" 2>/dev/null | tr '\t\n' '  ')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$session" "$tool" "$icon" "$age" "$path" "$desc"
  done
}

[ "${1:-}" = '--list' ] && { emit_rows; exit 0; }
[ "${1:-}" = '--list-rich' ] && { emit_rows_rich; exit 0; }

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-ai-session-manager: fzf is required for the picker"
  exit 0
fi

self="${BASH_SOURCE[0]}"
export FZF_DEFAULT_OPTS=''
sel=$(emit_rows_rich | fzf --ansi --delimiter='\t' --with-nth=4,3,6,7 \
  --reverse --cycle --header='enter: ir · ctrl-x: matar · esc: salir · escribí para filtrar' \
  --preview="$DIR/preview.sh {2} {6}" --preview-window='right,55%,wrap' \
  --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload($self --list-rich)")

[ -z "$sel" ] && exit 0
target=$(printf '%s' "$sel" | cut -f2)

origin=$(tmux show-options -qv -t "$target" @ai_origin 2>/dev/null)
[ -z "$origin" ] && origin=$(tmux show-options -qv -t "$target" @claude_origin 2>/dev/null)
parent=$(tmux show-options -gqv @ai_parent 2>/dev/null)
[ -z "$parent" ] && parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux attach-session -t "$target"
