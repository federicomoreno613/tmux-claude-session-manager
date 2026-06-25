#!/usr/bin/env python3
"""Project navigator data source.

Lists known projects from the engram `sessions` table (authoritative real
paths) with their memory count and the latest session-summary Goal, so you can
jump a terminal into a project by name while seeing its context/priorities.

Read-only on engram; nothing is written or committed. The repo hardcodes no
paths — everything comes from the local engram DB at runtime.

CLI: prints TSV rows -> name \\t path(~) \\t count \\t summary
"""
import os
import sqlite3
import sys

HOME = os.path.expanduser("~")
DB = os.path.join(HOME, ".engram", "engram.db")


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


def _pretty(d, namew):
    """Aligned display column: 'P1 name        ↳ what-I'm-doing' (note wins).
    The Pn badge is the manual priority level; blank padding keeps alignment."""
    prio = d.get("prio")
    badge = f"P{prio}" if prio else "  "
    name = d["project"]
    if len(name) > namew:
        name = name[: namew - 1] + "…"
    name = name.ljust(namew)
    note = (d.get("note") or "").replace("\t", " ").replace("\n", " ").strip()
    line = (d.get("line") or "").replace("\t", " ").replace("\n", " ").strip()
    if note:
        body = "✎ " + note
    elif line:
        body = "↳ " + line
    else:
        body = ""
    return f"{badge} {name}  {body}".rstrip()


def rows():
    """Projects ordered by the priorities digest (most important first), each
    enriched with its directory, pin star, and what-I'm-doing line."""
    import digest  # lazy: digest imports _goal from here, avoid circular import

    dmap = _dir_map()
    ranked = [d for d in digest.ranked() if d["project"] in dmap]
    namew = min(20, max((len(d["project"]) for d in ranked), default=8))
    out = []
    for d in ranked:
        path = dmap[d["project"]]
        disp = "~" + path[len(HOME):] if path.startswith(HOME) else path
        out.append((d["project"], disp, d.get("total", 0), _pretty(d, namew)))
    return out


if __name__ == "__main__":
    for name, path, count, pretty in rows():
        sys.stdout.write(f"{name}\t{path}\t{count}\t{pretty}\n")
