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
| `prefix` + `c` | Launch or re-attach a **Claude** session for the current directory |
| `prefix` + `x` | Launch or re-attach a **Codex** session for the current directory |
| `prefix` + `u` | Unified session picker (Codex + Claude) |
| `prefix` + `a` | **Cockpit**: live roster of every session/agent with state |
| `prefix` + `g` | Jump to the next session that's `waiting` for input |
| `prefix` + `Space` | One-key IDE layout (work pane + terminal + cockpit) |
| `prefix` + `p` | Project navigator, ranked by the priorities digest |
| `prefix` + `b` / `f` | **Back / forward** through visited windows (browser-style history) |
| `prefix` + `h` | Open/reuse a **Hermes** window (organizer copilot) |
| `prefix` + `e` | Open the current project in **VS Code** (`code`) |
| `prefix` + `o` | Open the current project in **Finder** (`open`) |

The cockpit shows two kinds of rows: **managed** sessions (launched with `c`/`x`, with
precise `waiting`/`working`/`idle` state from hooks) and **live** agents (any `claude`,
`codex` or `hermes` you run by hand in a pane, shown in cyan). Opening a project or launcher
**jumps to an existing window/session** instead of duplicating it.

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
set -g @ai_dashboard_key     'a'
set -g @ai_jump_key          'g'
set -g @ai_layout_key        'Space'
set -g @ai_projects_key      'p'
set -g @ai_back_key          'b'
set -g @ai_fwd_key           'f'
set -g @ai_hermes_key        'h'
set -g @ai_editor_key        'e'
set -g @ai_finder_key        'o'
set -g @codex_command        'codex'
set -g @claude_command       'claude'
set -g @ai_hermes_command    'hermes'
set -g @ai_editor_command    'code'
set -g @ai_detect_commands   'claude codex hermes'
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
- `history.sh` keeps a trail of visited windows in `@ai_hist`/`@ai_hist_idx` (fed by the
  `after-select-window` / `client-session-changed` hooks) so `prefix b`/`f` walk back and forward.
- The navigator and launchers reuse an existing window/session for a path (tagged `@ai_project`)
  instead of opening duplicates.

## License

[MIT](LICENSE) © Takuya Matsuyama. This fork keeps the upstream license.
