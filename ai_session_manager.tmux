#!/usr/bin/env bash
# tmux-ai-session-manager
#
# List, monitor status, and jump across nested Codex CLI and Claude Code
# sessions from a single popup. Based on craftzdog/tmux-claude-session-manager.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

codex_launch_key="$(get_tmux_option @codex_launch_key 'x')"
claude_launch_key="$(get_tmux_option @claude_launch_key 'c')"
list_key="$(get_tmux_option @ai_list_key 'u')"
dashboard_key="$(get_tmux_option @ai_dashboard_key 'a')"
jump_key="$(get_tmux_option @ai_jump_key 'g')"
layout_key="$(get_tmux_option @ai_layout_key 'Space')"
projects_key="$(get_tmux_option @ai_projects_key 'p')"

# Backward-compatible alias for people who still set the original option.
legacy_list_key="$(get_tmux_option @claude_list_key '')"
[ -n "$legacy_list_key" ] && list_key="$legacy_list_key"

# Launch (or re-attach to) an AI session for the current pane directory.
tmux bind-key "$codex_launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh codex '#{pane_current_path}' '#{window_id}'"

tmux bind-key "$claude_launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh claude '#{pane_current_path}' '#{window_id}'"

# Open the unified session picker. When pressed from inside a managed popup,
# list.sh closes that popup first so the picker opens full-size on the host.
tmux bind-key "$list_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{client_name}'"

# Persistent cockpit panel in a dedicated split pane (prefix a).
dashboard_split="$(get_tmux_option @ai_dashboard_split '-h')"
dashboard_size="$(get_tmux_option @ai_dashboard_size '40%')"
tmux bind-key "$dashboard_key" \
  split-window "$dashboard_split" -l "$dashboard_size" "exec $CURRENT_DIR/scripts/dashboard.py"

# Jump straight to the next session waiting for input (prefix g — Go).
tmux bind-key "$jump_key" \
  run-shell "$CURRENT_DIR/scripts/jump-waiting.sh"

# One-key IDE layout: work pane + spare terminal + cockpit (prefix Space).
tmux bind-key "$layout_key" \
  run-shell "$CURRENT_DIR/scripts/layout.sh '#{pane_current_path}'"

# Project navigator: pick a known project by name and open a terminal there (prefix p).
proj_w="$(get_tmux_option @ai_popup_width '80%')"
proj_h="$(get_tmux_option @ai_popup_height '70%')"
tmux bind-key "$projects_key" \
  display-popup -w "$proj_w" -h "$proj_h" -E "$CURRENT_DIR/scripts/projects.sh"

# Navegación atrás/adelante tipo browser (prefix b / prefix f). El trail de
# ventanas visitadas se alimenta por hooks; la lógica está en scripts/history.sh.
back_key="$(get_tmux_option @ai_back_key 'b')"
fwd_key="$(get_tmux_option @ai_fwd_key 'f')"
tmux bind-key "$back_key" run-shell "$CURRENT_DIR/scripts/history.sh back"
tmux bind-key "$fwd_key"  run-shell "$CURRENT_DIR/scripts/history.sh forward"
# Overwrite (no -a) para ser idempotente al re-sourcear el tmux.conf.
tmux set-hook -g after-select-window    "run-shell -b '$CURRENT_DIR/scripts/history.sh push'"
tmux set-hook -g client-session-changed "run-shell -b '$CURRENT_DIR/scripts/history.sh push'"

# Hermes como ciudadano de primera: prefix h abre/reusa una ventana dedicada
# (idempotente, persiste al detach).
hermes_key="$(get_tmux_option @ai_hermes_key 'h')"
tmux bind-key "$hermes_key" run-shell "$CURRENT_DIR/scripts/hermes.sh"

# Abrir el proyecto (dir del pane actual) en el editor o en Finder, sin soltar el
# teclado:  prefix e -> VS Code (editor) ·  prefix o -> Finder (open).
# open-editor.sh resuelve `code` de forma robusta (run-shell no siempre hereda tu PATH).
editor_key="$(get_tmux_option @ai_editor_key 'e')"
finder_key="$(get_tmux_option @ai_finder_key 'o')"
tmux bind-key "$editor_key" run-shell "$CURRENT_DIR/scripts/open-editor.sh '#{pane_current_path}'"
tmux bind-key "$finder_key" run-shell "open '#{pane_current_path}'"

# Optional status-bar widget (opt-in via @ai_statusbar on). Prepends a compact
# count to status-right without clobbering the user's existing value.
if [ "$(get_tmux_option @ai_statusbar 'off')" = "on" ]; then
  current_status_right="$(tmux show-option -gqv status-right)"
  case "$current_status_right" in
    *"$CURRENT_DIR/scripts/status.sh"*) ;;  # already wired, don't double-add
    *)
      tmux set-option -g status-interval "$(get_tmux_option @ai_status_interval '5')"
      tmux set-option -g status-right "#($CURRENT_DIR/scripts/status.sh) ${current_status_right}"
      ;;
  esac
fi
