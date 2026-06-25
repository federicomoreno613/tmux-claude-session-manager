#!/usr/bin/env bash
# Edit a project's priority note (HIL) from the navigator (prefix p -> ctrl-o).
# Safe-by-default semantics — never delete a note by accident:
#   text + Enter -> save/replace the note
#   "-"  + Enter -> delete the existing note (explicit gesture)
#   empty / Esc  -> cancel, leave the note untouched
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name="${1:-}"
[ -n "$name" ] || exit 0

printf '\nNota para %s (texto=guardar · "-"=borrar · vacío/Esc=cancelar): ' "$name" > /dev/tty
IFS= read -r note < /dev/tty || exit 0
# A bare Esc lands here as a control char (\x1b), not as empty input; strip
# control chars so "Esc then Enter" reads as cancel, not as a note to save.
clean="$(printf '%s' "$note" | tr -d '[:cntrl:]')"

if [ -z "$clean" ]; then
  exit 0                                    # cancel: leave the note untouched
elif [ "$clean" = "-" ]; then
  python3 "$DIR/digest.py" --clear-note "$name"
else
  python3 "$DIR/digest.py" --note "$name" "$clean"
fi
