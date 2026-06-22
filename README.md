# tmux-ai-session-manager

Fork of [craftzdog/tmux-claude-session-manager](https://github.com/craftzdog/tmux-claude-session-manager) adapted to manage both **Codex CLI** and **Claude Code** sessions in tmux.

Run many AI coding sessions across your projects, each in its own tmux session, then list them, see which are done vs. still working, preview their panes, jump back to the launching window, and resume them from a single popup.

## Prerequisites

- tmux >= 3.2, for `display-popup`
- [fzf](https://github.com/junegunn/fzf)
- `codex` CLI
- `claude` CLI
- bash; macOS or Linux

## Manual install

```sh
git clone https://github.com/federicomoreno613/tmux-claude-session-manager ~/.config/tmux/plugins/tmux-ai-session-manager
```

Add this to `~/.tmux.conf`, then reload tmux:

```tmux
set -g @codex_launch_key 'x'
set -g @claude_launch_key 'c'
set -g @ai_list_key 'u'
run-shell ~/.config/tmux/plugins/tmux-ai-session-manager/ai_session_manager.tmux
```

## Usage

| Key | Action |
| --- | --- |
| `prefix` + `x` | Launch or re-attach to a Codex session for the current directory |
| `prefix` + `c` | Launch or re-attach to a Claude session for the current directory |
| `prefix` + `u` | Open the unified session picker |

Inside the picker:

| Key | Action |
| --- | --- |
| `enter` | Jump to the selected session and resume it in the popup |
| `ctrl-x` | Kill the highlighted session |
| arrows / type | Navigate and filter with fzf |

Sessions needing attention (`waiting`, `idle`) sort toward the top.

## Options

Set options before loading `ai_session_manager.tmux`:

```tmux
set -g @codex_launch_key     'x'
set -g @claude_launch_key    'c'
set -g @ai_list_key          'u'
set -g @codex_command        'codex'
set -g @claude_command       'claude'
set -g @codex_session_prefix 'codex-'
set -g @claude_session_prefix 'claude-'
set -g @ai_popup_width       '90%'
set -g @ai_popup_height      '90%'
```

The original `claude_session_manager.tmux` entrypoint remains as a backward-compatible wrapper.

## Status hooks

Status is optional. Without hooks, the picker still lists sessions with `?` status.

The status script supports both tools:

```sh
~/.config/tmux/plugins/tmux-ai-session-manager/scripts/state.sh codex working
~/.config/tmux/plugins/tmux-ai-session-manager/scripts/state.sh claude idle
```

Recommended state machine:

| Event | State | Meaning |
| --- | --- | --- |
| Prompt submitted | `working` | Agent is busy |
| Permission/user input needed | `waiting` | Needs attention |
| Turn stopped | `idle` | Your move |

## How it works

- Launchers create detached `codex-<hash-of-dir>` or `claude-<hash-of-dir>` tmux sessions.
- The launching window is recorded in `@ai_origin` so the picker can jump back before reopening the popup.
- Hooks stamp `@ai_state`, `@ai_state_at`, and `@ai_tool` onto each session.
- The picker lists both managed prefixes and uses `tmux capture-pane` for live previews.

## License

[MIT](LICENSE) © Takuya Matsuyama. This fork keeps the upstream license.
