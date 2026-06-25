#!/usr/bin/env bash
# Compact status-bar widget: counts managed sessions by state.
# Prints e.g.  "#[fg=yellow]● 2 waiting#[default] · 1 working"
# Empty output when there are no managed sessions (keeps the bar clean).
# Fast: reads only tmux options, never touches the per-project context cache.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"
# shellcheck source=rows.sh
. "$DIR/rows.sh"

waiting=0 working=0 idle=0 live=0 unknown=0
while IFS=$'\t' read -r rank _rest; do
  case "$rank" in
    0) waiting=$((waiting + 1)) ;;
    1) idle=$((idle + 1)) ;;
    3) working=$((working + 1)) ;;
    4) live=$((live + 1)) ;;
    *) unknown=$((unknown + 1)) ;;
  esac
done < <(emit_rows)

total=$((waiting + working + idle + live + unknown))
[ "$total" -eq 0 ] && exit 0

parts=()
[ "$waiting" -gt 0 ] && parts+=("#[fg=yellow]● ${waiting} waiting#[default]")
[ "$working" -gt 0 ] && parts+=("${working} working")
[ "$idle" -gt 0 ] && parts+=("${idle} idle")
[ "$live" -gt 0 ] && parts+=("#[fg=cyan]${live} live#[default]")

# Join with " · ".
out=""
for p in "${parts[@]}"; do
  if [ -z "$out" ]; then out="$p"; else out="$out · $p"; fi
done
printf '%s' "$out"
