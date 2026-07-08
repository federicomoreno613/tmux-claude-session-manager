#!/usr/bin/env bash
# Abrir un directorio en el editor, robusto ante PATH incompleto (tmux run-shell
# no siempre hereda tu PATH interactivo, así que `code` puede no resolverse).
# Orden: `code` en PATH -> ruta típica de Homebrew -> `open -a "Visual Studio Code"`
# -> Finder como último recurso. Uso: open-editor.sh [dir]
set -uo pipefail
dir="${1:-$PWD}"
case "$dir" in "~"*) dir="$HOME${dir#\~}" ;; esac

if command -v code >/dev/null 2>&1; then
  exec code "$dir"
elif [ -x /opt/homebrew/bin/code ]; then
  exec /opt/homebrew/bin/code "$dir"
elif [ -d "/Applications/Visual Studio Code.app" ]; then
  exec open -a "Visual Studio Code" "$dir"
else
  exec open "$dir"
fi
