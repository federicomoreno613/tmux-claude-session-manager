#!/usr/bin/env python3
"""Live AI cockpit for tmux — persistent panel of Codex/Claude sessions.

Runs inside a dedicated tmux pane (bound to `prefix a`). Auto-refreshes, pins
sessions that need input at the top, marks the session you are currently inside,
and shows a compact summary. Reuses `picker.sh --list` for session enumeration,
ranking and colors so there is a single source of truth.

M1 scope: state + folder + current marker + counts. Per-project context badges
and the project summary line land in a later milestone (context.py); the
optional orchestrator section comes after that.
"""
import os
import select
import shutil
import signal
import subprocess
import sys
import termios
import time
import tty

DIR = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")

# Per-project context (badges + engram summary). Same dir; degrade gracefully.
sys.path.insert(0, DIR)
try:
    import context as _context
except Exception:
    _context = None
try:
    import firstmate as _firstmate
except Exception:
    _firstmate = None

# ANSI helpers.
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
INVERSE = "\033[7m"
YELLOW = "\033[33m"
GREEN = "\033[32m"
RED = "\033[31m"
GREY = "\033[90m"
CLEAR = "\033[H\033[2J"
HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"

RANK_STATE = {"0": "waiting", "1": "idle", "2": "?", "3": "working", "4": "live"}
CYAN = "\033[36m"


def tmux_opt(name, default):
    try:
        out = subprocess.run(
            ["tmux", "show-option", "-gqv", name],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        return out if out else default
    except Exception:
        return default


def get_rows():
    """Return list of dicts from `picker.sh --list` (pre-sorted by rank, age)."""
    try:
        out = subprocess.run(
            [os.path.join(DIR, "picker.sh"), "--list"],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except Exception:
        return []
    rows = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 6:
            continue
        rank, session, tool, icon, age, path = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
        rows.append({
            "rank": rank,
            "session": session,
            "tool": tool.strip(),
            "icon": icon,
            "age": age.strip(),
            "path": path,
            "state": RANK_STATE.get(rank, "?"),
        })
    return rows


def attached_sessions():
    """Names of managed sessions that currently have a client attached."""
    try:
        out = subprocess.run(
            ["tmux", "list-clients", "-F", "#{session_name}"],
            capture_output=True, text=True, timeout=2,
        ).stdout
        return {s for s in out.split() if s}
    except Exception:
        return set()


def render(rows, attached, width):
    counts = {"waiting": 0, "idle": 0, "working": 0, "?": 0, "live": 0}
    for r in rows:
        counts[r["state"]] = counts.get(r["state"], 0) + 1

    clock = time.strftime("%H:%M:%S")
    summary = (
        f"{YELLOW}● {counts['waiting']} waiting{RESET} · "
        f"{RED}{counts['working']} working{RESET} · "
        f"{GREEN}{counts['idle']} idle{RESET}"
    )
    if counts["live"]:
        summary += f" · {CYAN}{counts['live']} live{RESET}"
    rule = DIM + "─" * min(width, 70) + RESET

    lines = []
    lines.append(f"{BOLD} AI Cockpit{RESET}   {DIM}{clock}{RESET}   {summary}")
    lines.append(rule)

    if not rows:
        lines.append(f"{DIM} No hay sesiones AI abiertas. prefix c / prefix x para lanzar.{RESET}")
    else:
        waiting = [r for r in rows if r["state"] == "waiting"]
        rest = [r for r in rows if r["state"] != "waiting"]
        if waiting:
            lines.append(f"{BOLD}{YELLOW} NECESITAN INPUT{RESET}")
            for r in waiting:
                lines.extend(fmt_row(r, attached, width, highlight=True))
            lines.append("")
        for r in rest:
            lines.extend(fmt_row(r, attached, width, highlight=False))

    # Optional FirstMate section — DEPRECADO (2026-07-08): FirstMate quedó
    # reemplazado por Hermes como orquestador. Se deja gateado en off por
    # @ai_firstmate (default off) y no se usa; sobrevive por si se reactiva.
    if _firstmate and tmux_opt("@ai_firstmate", "off") == "on":
        fm = _firstmate.get_firstmate(tmux_opt("@ai_firstmate_path", "") or None)
        if fm is not None:
            lines.append(rule)
            inflight = fm["in_flight"]
            head = (
                f"{BOLD} FIRSTMATE{RESET}  {len(inflight)} in-flight · "
                f"{len(fm['queued'])} queued · {len(fm['done'])} done"
            )
            if fm["windows"]:
                head += f" · {CYAN}{len(fm['windows'])} fm{RESET}"
            lines.append(head)
            for item in inflight[:5]:
                if len(item) > width - 6:
                    item = item[: width - 7] + "…"
                lines.append(f"   {YELLOW}•{RESET} {item}")
            if not inflight and not fm["queued"]:
                lines.append(f"   {DIM}sin tareas en el backlog{RESET}")

    lines.append(rule)
    lines.append(
        f"{DIM} prefix g{RESET} ir a waiting   "
        f"{DIM}prefix u{RESET} picker   "
        f"{DIM}prefix d{RESET} salir   "
        f"{DIM}q{RESET} cerrar panel"
    )
    return "\n".join(lines)


def _ctx(path):
    if _context is None:
        return {}
    try:
        return _context.get_context(path)
    except Exception:
        return {}


def _badges(ctx):
    b = []
    if ctx.get("claude_md"):
        b.append("C")
    if ctx.get("agents_md"):
        b.append("A")
    if ctx.get("skills"):
        b.append(f"sk:{ctx['skills']}")
    if ctx.get("agents"):
        b.append(f"ag:{ctx['agents']}")
    if ctx.get("engram_count"):
        b.append(f"eng:{ctx['engram_count']}")
    return " ".join(b)


def fmt_row(r, attached, width, highlight):
    """Return a list of display lines for one row (main + optional summary)."""
    marker = f"{BOLD}▸{RESET}" if r["session"] in attached else " "
    tool = f"{r['tool']:<6}"
    age = f"{r['age']:>4}"
    # Abbreviate $HOME to ~ for the displayed path; keep the real path for ctx.
    real = r["path"]
    if real.startswith("~"):
        real = HOME + real[1:]
    disp = real
    if disp == HOME:
        disp = "~"
    elif disp.startswith(HOME + "/"):
        disp = "~" + disp[len(HOME):]

    ctx = _ctx(real)
    badges = _badges(ctx)
    # Budget: marker+icon+tool+age+spacing ~26 cols, plus badges.
    reserve = 26 + (len(badges) + 2 if badges else 0)
    avail = max(8, width - reserve)
    if len(disp) > avail:
        disp = "…" + disp[-(avail - 1):]

    main = f" {marker} {r['icon']}  {tool} {age}  {disp}"
    if badges:
        main += f"  {DIM}{badges}{RESET}"

    out = [main]
    summary = ctx.get("summary") or ""
    if summary:
        s_avail = max(10, width - 6)
        if len(summary) > s_avail:
            summary = summary[: s_avail - 1] + "…"
        out.append(f"     {DIM}↳ {summary}{RESET}")
    return out


def main():
    interval = float(tmux_opt("@ai_dashboard_refresh", "2") or "2")
    is_tty = sys.stdin.isatty()
    old_attrs = None
    if is_tty:
        try:
            old_attrs = termios.tcgetattr(sys.stdin)
            tty.setcbreak(sys.stdin.fileno())
        except Exception:
            old_attrs = None

    # Force an immediate redraw on terminal resize.
    resized = {"flag": True}
    try:
        signal.signal(signal.SIGWINCH, lambda *_: resized.__setitem__("flag", True))
    except Exception:
        pass

    sys.stdout.write(HIDE_CURSOR)
    sys.stdout.flush()
    try:
        while True:
            try:
                size = shutil.get_terminal_size((80, 24))
                frame = render(get_rows(), attached_sessions(), size.columns)
                sys.stdout.write(CLEAR + frame)
                sys.stdout.flush()
                resized["flag"] = False
            except Exception:
                # Never let a transient tmux/render error kill the loop.
                pass

            if is_tty:
                r, _, _ = select.select([sys.stdin], [], [], interval)
                if r:
                    ch = sys.stdin.read(1)
                    if ch in ("q", "Q", "\x03"):  # q or Ctrl-C
                        break
            else:
                time.sleep(interval)
    except KeyboardInterrupt:
        pass
    finally:
        if old_attrs is not None:
            try:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_attrs)
            except Exception:
                pass
        sys.stdout.write(SHOW_CURSOR + RESET + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
