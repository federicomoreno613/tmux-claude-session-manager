#!/usr/bin/env bash
# Cross-platform desktop notification.
# Usage: notify.sh <title> <message>
# macOS  : terminal-notifier if present, else osascript.
# Linux  : notify-send if present.
# Other  : best-effort tmux display-message; never errors.
set -uo pipefail

title="${1:-AI session}"
msg="${2:-}"

case "$(uname)" in
  Darwin)
    if command -v terminal-notifier >/dev/null 2>&1; then
      terminal-notifier -title "$title" -message "$msg" -sound default >/dev/null 2>&1
    elif command -v osascript >/dev/null 2>&1; then
      # Escape backslashes and double quotes for the AppleScript string literals.
      esc_title=$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')
      esc_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
      osascript -e "display notification \"$esc_msg\" with title \"$esc_title\" sound name \"Submarine\"" >/dev/null 2>&1
    fi
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$title" "$msg" >/dev/null 2>&1
    fi
    ;;
esac

# Best-effort in-terminal signal regardless of platform (no-op outside tmux).
if [ -n "${TMUX:-}" ]; then
  tmux display-message "$title: $msg" 2>/dev/null || true
fi
exit 0
