#!/usr/bin/env bash
# Backward-compatible entrypoint. Prefer ai_session_manager.tmux.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$CURRENT_DIR/ai_session_manager.tmux" "$@"
