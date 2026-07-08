#!/usr/bin/env python3
"""Cross-project priorities digest.

Reads the engram `sessions`/`observations` tables (read-only) for ALL known
projects and answers "what is priority right now", ranked across projects, so
the project navigator (prefix p) can show it on top.

Per project it derives, from the latest session_summary:
  - line   : the first "## Next Steps" bullet (what to do next), else the Goal
  - recent : observations in the last 7 days (how active it is right now)
  - last   : most recent session start (how fresh it is)

Ranking score (transparent, see _score): a recency term that decays with days
since last activity, plus the 7-day activity count as a weight. Most recently
touched + most active projects float to the top.

Patterns mirror projects.py / context.py: engram opened READ-ONLY, no hardcoded
paths, failures degrade to empty, and the whole digest is cached under ~/.cache
(cross-project queries are heavier, so we cache the result, not per-project).

CLI:
  digest.py            -> JSON (debug): ranked projects with score + signals
  digest.py --header   -> compact block for fzf --header (prefix p)
"""
import json
import math
import os
import sqlite3
import subprocess
import sys
import time

# Reuse the Goal extractor and DB conventions from the sibling navigator script.
# realpath (not abspath) so this resolves correctly when invoked via a symlink
# (e.g. ~/.local/bin/fm-digest), keeping projects.py importable.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from projects import _goal  # noqa: E402

HOME = os.path.expanduser("~")
DB = os.path.join(HOME, ".engram", "engram.db")
CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")),
    "tmux-ai-session-manager",
)
CACHE_FILE = os.path.join(CACHE_DIR, "digest.json")
# Human-in-the-loop overrides (local, machine-only, never in the repo). Lets you
# pin a project to the top and attach a forward-looking note that engram does not
# capture. Applied live on top of the cached engram facts.
OVERRIDES_FILE = os.path.join(CACHE_DIR, "overrides.json")


def _tmux_opt(name, default):
    try:
        out = subprocess.run(
            ["tmux", "show-option", "-gqv", name],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        return out if out else default
    except Exception:
        return default


TTL = float(_tmux_opt("@ai_digest_ttl", "300") or "300")
TOP = int(_tmux_opt("@ai_digest_top", "6") or "6")


def _next_steps(content):
    """First 'real' line under '## Next Steps' in a session_summary, if any."""
    if not content:
        return ""
    lines = content.splitlines()
    for i, ln in enumerate(lines):
        if ln.strip().lower().startswith("## next steps"):
            for nxt in lines[i + 1:]:
                s = nxt.strip()
                if not s:
                    continue
                if s.startswith("#"):  # next section -> no items
                    break
                # Strip a leading bullet/number marker.
                for mark in ("- ", "* ", "1. ", "2. ", "3. "):
                    if s.startswith(mark):
                        s = s[len(mark):].strip()
                        break
                return s
            break
    return ""


def _days_since(ts):
    """Days between an engram timestamp (UTC 'YYYY-MM-DD HH:MM:SS') and now."""
    if not ts:
        return 9999.0
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
        try:
            t = time.strptime(ts[:19], fmt)
            return max(0.0, (time.time() - time.mktime(t)) / 86400.0)
        except Exception:
            continue
    return 9999.0


def _score(days, recent):
    """Higher = more priority. Recency decays exponentially (~7-day half-life);
    7-day activity count adds a linear weight so busy projects rank up."""
    recency = math.exp(-days / 7.0)  # 1.0 today -> ~0.37 at 7d -> ~0.14 at 14d
    return round(recency * 10.0 + float(recent), 3)


def _ago(days):
    """Human relative time ('recién' / 'hace 2h' / 'ayer' / 'hace 3d' / 'hace 2
    sem' / 'hace 1 mes') from the digest's `days` float. Empty if unknown."""
    try:
        d = float(days)
    except (TypeError, ValueError):
        return ""
    if d < 0 or d >= 9000:  # 9999 is _days_since's "unknown" sentinel
        return ""
    hours = d * 24.0
    if hours < 1:
        return "recién"
    if d < 1:
        return f"hace {int(hours)}h"
    if d < 2:
        return "ayer"
    if d < 7:
        return f"hace {int(d)}d"
    if d < 30:
        return f"hace {int(d / 7)} sem"
    return f"hace {int(d / 30)} mes"


def _compute():
    if not os.path.isfile(DB):
        return []
    try:
        con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=1.0)
        con.execute("PRAGMA busy_timeout=500")
        cur = con.cursor()
        rows = cur.execute(
            "SELECT project, directory, MAX(started_at) AS t FROM sessions "
            "WHERE directory IS NOT NULL AND directory<>'' "
            "GROUP BY project ORDER BY t DESC"
        ).fetchall()
        seen, out = set(), []
        for project, directory, last in rows:
            if not directory or not os.path.isdir(directory) or directory in seen:
                continue
            seen.add(directory)
            (recent,) = cur.execute(
                "SELECT count(*) FROM observations WHERE project=? "
                "AND deleted_at IS NULL "
                "AND created_at > datetime('now','-7 days')",
                (project,),
            ).fetchone()
            (total,) = cur.execute(
                "SELECT count(*) FROM observations WHERE project=? "
                "AND deleted_at IS NULL",
                (project,),
            ).fetchone()
            srow = cur.execute(
                "SELECT content FROM observations WHERE project=? "
                "AND type='session_summary' AND deleted_at IS NULL "
                "ORDER BY created_at DESC, id DESC LIMIT 1",
                (project,),
            ).fetchone()
            content = srow[0] if srow else ""
            line = _next_steps(content) or _goal(content)
            # Last few non-summary observation titles: "what happened lately".
            trows = cur.execute(
                "SELECT title FROM observations WHERE project=? "
                "AND deleted_at IS NULL AND type<>'session_summary' "
                "AND title IS NOT NULL AND title<>'' "
                "ORDER BY created_at DESC, id DESC LIMIT 3",
                (project,),
            ).fetchall()
            recent_titles = [t[0] for t in trows]
            days = _days_since(last)
            out.append({
                "project": project,
                "line": line,
                "recent": recent,
                "total": total,
                "days": round(days, 2),
                "score": _score(days, recent),
                "recent_titles": recent_titles,
            })
        con.close()
        out.sort(key=lambda d: d["score"], reverse=True)
        return out
    except Exception:
        return []


def digest():
    """Engram-derived ranked facts, refreshing the cache past TTL.

    The cache holds ONLY engram facts; HIL overrides are layered live in
    ranked() so a pin/note change is reflected instantly.
    """
    now = time.time()
    try:
        with open(CACHE_FILE) as fh:
            cached = json.load(fh)
        if (now - cached.get("_at", 0)) <= TTL and "projects" in cached:
            return cached["projects"]
    except Exception:
        pass
    projects = _compute()
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        with open(tmp, "w") as fh:
            json.dump({"_at": now, "projects": projects}, fh)
        os.replace(tmp, CACHE_FILE)
    except Exception:
        pass
    return projects


def _load_overrides():
    try:
        with open(OVERRIDES_FILE) as fh:
            return json.load(fh)
    except Exception:
        return {}


def _save_overrides(ov):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = OVERRIDES_FILE + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(ov, fh, ensure_ascii=False)
        os.replace(tmp, OVERRIDES_FILE)
    except Exception:
        pass


MAX_PRIO = 3  # priority levels P1..P3 (1 = most important)


def _prio_of(entry):
    """Priority level of an override entry, with back-compat for the old
    boolean `pinned` (pinned:true -> P1)."""
    p = entry.get("prio")
    if isinstance(p, int) and 1 <= p <= MAX_PRIO:
        return p
    if entry.get("pinned"):
        return 1
    return None


def set_prio(name, level):
    """Set a priority level (1..MAX_PRIO) or clear it with level falsy/0."""
    ov = _load_overrides()
    entry = ov.get(name, {})
    entry.pop("pinned", None)  # migrate away from the old boolean
    if level and 1 <= int(level) <= MAX_PRIO:
        entry["prio"] = int(level)
    else:
        entry.pop("prio", None)
    if entry:
        ov[name] = entry
    else:
        ov.pop(name, None)
    _save_overrides(ov)


def cycle_prio(name):
    """none -> P1 -> P2 -> P3 -> none. Lets one key walk the priority list."""
    cur = _prio_of(_load_overrides().get(name, {}))
    nxt = 1 if cur is None else (cur + 1)
    set_prio(name, nxt if nxt <= MAX_PRIO else 0)


def set_note(name, text):
    ov = _load_overrides()
    entry = ov.get(name, {})
    text = (text or "").strip()
    if text:
        entry["note"] = text
    else:
        entry.pop("note", None)
    if entry:
        ov[name] = entry
    else:
        ov.pop(name, None)
    _save_overrides(ov)


def ranked():
    """Engram facts + HIL overlay. Manually-prioritized projects (P1<P2<P3) lead,
    ordered by level then engram score; the rest follow by score. The note is
    attached alongside (it never replaces the engram line). This is what both the
    navigator and FirstMate consume."""
    ov = _load_overrides()
    items = []
    for d in digest():
        o = ov.get(d["project"], {})
        prio = _prio_of(o)
        items.append({
            **d,
            "prio": prio,              # 1..3 or None
            "pinned": prio is not None,  # back-compat flag for FirstMate
            "note": o.get("note", ""),
        })
    # Prioritized first (by level), then everything by engram score.
    items.sort(key=lambda d: (d["prio"] if d["prio"] else 99, -d["score"]))
    return items


def _prio_badge(prio):
    return f"P{prio}" if prio else ""


def header(top=TOP, maxlen=58):
    """Compact multi-line block for fzf --header."""
    out = ["PRIORIDADES AHORA"]
    for d in ranked()[:top]:
        badge = _prio_badge(d.get("prio"))
        badge = (badge + " ") if badge else ""
        note = (d.get("note") or "").replace("\t", " ").replace("\n", " ").strip()
        line = (d.get("line") or "").replace("\t", " ").replace("\n", " ").strip()
        tag = f" (7d:{d['recent']})" if d.get("recent") else ""
        if note:  # your intent leads; the engram next-step trails if it fits
            body = f"✎ {note}"
            if line and len(body) + len(line) + 5 < maxlen:
                body = f"{body} · ↳ {line}"
        else:
            body = f"↳ {line}" if line else ""
        if len(body) > maxlen:
            body = body[: maxlen - 1] + "…"
        out.append(f"  {badge}{d['project']}  {body}{tag}".rstrip())
    return "\n".join(out)


def detail(name):
    """Rich, multi-line context for one project (navigator preview pane).
    Reads only the cached ranked() data — cheap enough to run on every cursor
    move."""
    d = next((x for x in ranked() if x["project"] == name), None)
    if not d:
        return ""
    C = {"hdr": "\033[1m", "dim": "\033[2m", "y": "\033[33m", "off": "\033[0m"}
    out = []
    prio = _prio_badge(d.get("prio"))
    bits = []
    if prio:
        bits.append(f"{C['y']}{prio}{C['off']}")
    ago = _ago(d.get("days"))
    if ago:
        bits.append(ago)
    bits.append(f"score {d['score']}")
    if d.get("recent"):
        bits.append(f"7d:{d['recent']}")
    if d.get("total"):
        bits.append(f"{d['total']} memorias")
    out.append(" · ".join(bits))
    # "Qué hice" (backward) clearly separated from "qué quería hacer" (forward).
    titles = d.get("recent_titles") or []
    if titles:
        out.append(f"{C['hdr']}✓ lo último que hiciste{C['off']}")
        for t in titles:
            out.append(f"{C['dim']}  · {t}{C['off']}")
    if d.get("note"):
        out.append(f"{C['y']}✎ nota (tu intención): {d['note']}{C['off']}")
    if d.get("line"):
        out.append(f"{C['hdr']}↳ qué querías hacer{C['off']} {d['line']}")
    return "\n".join(out)


def _usage():
    sys.stderr.write(
        "usage: digest.py [--header | --detail NAME | --cycle-prio NAME | "
        "--set-prio NAME N | --clear-prio NAME | --note NAME [TEXT] | "
        "--clear-note NAME | --json]\n"
    )


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    if cmd == "--header":
        print(header())
    elif cmd == "--detail" and len(args) >= 2:
        print(detail(args[1]))
    elif cmd == "--cycle-prio" and len(args) >= 2:
        cycle_prio(args[1])
    elif cmd == "--set-prio" and len(args) >= 3:
        set_prio(args[1], int(args[2]))
    elif cmd == "--clear-prio" and len(args) >= 2:
        set_prio(args[1], 0)
    elif cmd == "--toggle-pin" and len(args) >= 2:  # back-compat: P1 toggle
        set_prio(args[1], 0 if _prio_of(_load_overrides().get(args[1], {})) else 1)
    elif cmd == "--note" and len(args) >= 2:
        set_note(args[1], " ".join(args[2:]))  # empty TEXT clears the note
    elif cmd == "--clear-note" and len(args) >= 2:
        set_note(args[1], "")
    elif cmd in ("", "--json"):
        print(json.dumps(ranked(), indent=2, ensure_ascii=False))
    else:
        _usage()
        sys.exit(2)
