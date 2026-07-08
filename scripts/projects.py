#!/usr/bin/env python3
"""Project navigator data source.

Lists known projects from the engram `sessions` table (authoritative real
paths) with their memory count and the latest session-summary Goal, so you can
jump a terminal into a project by name while seeing its context/priorities.

Read-only on engram; nothing is written or committed. The repo hardcodes no
paths — everything comes from the local engram DB at runtime.

CLI: prints TSV rows -> name \\t path(~) \\t count \\t summary
"""
import glob
import os
import sqlite3
import subprocess
import sys

HOME = os.path.expanduser("~")
DB = os.path.join(HOME, ".engram", "engram.db")

# Freshness buckets shown as group separators in the navigator. Pinned projects
# (a manual P1/P2/P3) lead in their own bucket so intent and recency both show.
BUCKETS = ["📌 Fijados", "Hoy", "Esta semana", "Antes"]


def _tmux_opt(name, default):
    try:
        out = subprocess.run(
            ["tmux", "show-option", "-gqv", name],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        return out or default
    except Exception:
        return default


def _crew_paths():
    """Abs project paths that currently have a live FirstMate crew window (fm-*).
    Maps live `fm-<id>` tmux windows to their project via FirstMate's
    state/<id>.meta. Surfaces work FirstMate abstracts away from the captain."""
    fmpath = os.path.expanduser(_tmux_opt("@ai_firstmate_path", os.path.join(HOME, "firstmate")))
    statedir = os.path.join(fmpath, "state")
    if not os.path.isdir(statedir):
        return set()
    try:
        wins = subprocess.run(
            ["tmux", "list-windows", "-a", "-F", "#{window_name}"],
            capture_output=True, text=True, timeout=2,
        ).stdout.split()
    except Exception:
        return set()
    live_ids = {w[3:] for w in wins if w.startswith("fm-")}
    if not live_ids:
        return set()
    out = set()
    for meta in glob.glob(os.path.join(statedir, "*.meta")):
        if os.path.basename(meta)[:-5] not in live_ids:
            continue
        try:
            with open(meta, encoding="utf-8") as fh:
                for ln in fh:
                    if ln.startswith("project="):
                        p = ln.split("=", 1)[1].strip()
                        if p:
                            out.add(os.path.abspath(p))
                        break
        except Exception:
            pass
    return out


def _bucket(d):
    """Which freshness group a project falls in (pinned wins over recency)."""
    if d.get("prio"):
        return "📌 Fijados"
    try:
        days = float(d.get("days"))
    except (TypeError, ValueError):
        return "Antes"
    if days < 1:
        return "Hoy"
    if days < 7:
        return "Esta semana"
    return "Antes"


def _goal(content):
    """First line under '## Goal' in a session_summary, else first prose line."""
    if not content:
        return ""
    lines = content.splitlines()
    for i, ln in enumerate(lines):
        if ln.strip().lower().startswith("## goal"):
            for nxt in lines[i + 1:]:
                if nxt.strip():
                    return nxt.strip()
            break
    for ln in lines:
        s = ln.strip()
        if s and not s.startswith("#"):
            return s
    return ""


def _dir_map():
    """project -> real directory, from the engram sessions table (latest wins,
    deduped by directory, only existing dirs). Same source as before."""
    if not os.path.isfile(DB):
        return {}
    try:
        con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=1.0)
        con.execute("PRAGMA busy_timeout=500")
        cur = con.cursor()
        rows = cur.execute(
            "SELECT project, directory, MAX(started_at) AS t FROM sessions "
            "WHERE directory IS NOT NULL AND directory<>'' "
            "GROUP BY project ORDER BY t DESC"
        ).fetchall()
        con.close()
        seen, out = set(), {}
        for project, directory, _t in rows:
            if not directory or not os.path.isdir(directory) or directory in seen:
                continue
            seen.add(directory)
            out[project] = directory
        return out
    except Exception:
        return {}


def _header_row(label):
    """A non-selectable freshness separator (blue/bold). Empty name+path so the
    navigator's enter/key binds no-op on it."""
    return ("", "", 0, f"\033[1m\033[34m── {label} ──\033[0m")


def _pretty(d, namew, crew_active):
    """Aligned display column:
        'P1 name      hace 2h  🤖 ↳ what-I'm-doing' (note wins over next-step).
    The Pn badge is the manual priority; the dim time answers 'how fresh', the
    robot marks a project FirstMate is actively crewing right now."""
    import digest  # lazy: avoid circular import at module load

    prio = d.get("prio")
    badge = f"P{prio}" if prio else "  "
    name = d["project"]
    if len(name) > namew:
        name = name[: namew - 1] + "…"
    name = name.ljust(namew)
    ago = digest._ago(d.get("days"))
    agocol = f"\033[2m{ago.rjust(9)}\033[0m" if ago else " " * 9
    crew = "\033[36m🤖\033[0m " if crew_active else ""
    note = (d.get("note") or "").replace("\t", " ").replace("\n", " ").strip()
    line = (d.get("line") or "").replace("\t", " ").replace("\n", " ").strip()
    if note:
        body = "✎ " + note
    elif line:
        body = "↳ " + line
    else:
        body = ""
    return f"{badge} {name}  {agocol}  {crew}{body}".rstrip()


def rows():
    """Projects grouped by freshness (pinned first), each enriched with its
    directory, relative time, and a live-crew marker. Group separators are
    emitted as header rows with an empty name/path."""
    import digest  # lazy: digest imports _goal from here, avoid circular import

    dmap = _dir_map()
    ranked = [d for d in digest.ranked() if d["project"] in dmap]
    crew = _crew_paths()
    namew = min(20, max((len(d["project"]) for d in ranked), default=8))
    groups = {b: [] for b in BUCKETS}
    for d in ranked:  # ranked() is pre-sorted (pinned by level, then score)
        groups[_bucket(d)].append(d)
    out = []
    for bucket in BUCKETS:
        members = groups[bucket]
        if not members:
            continue
        out.append(_header_row(bucket))
        for d in members:
            path = dmap[d["project"]]
            disp = "~" + path[len(HOME):] if path.startswith(HOME) else path
            active = os.path.abspath(path) in crew
            out.append((d["project"], disp, d.get("total", 0), _pretty(d, namew, active)))
    return out


if __name__ == "__main__":
    for name, path, count, pretty in rows():
        sys.stdout.write(f"{name}\t{path}\t{count}\t{pretty}\n")
