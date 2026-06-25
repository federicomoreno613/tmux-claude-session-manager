#!/usr/bin/env python3
"""Per-project context for the cockpit, with caching.

For a given project directory returns compact indicators:
  - claude_md / agents_md : whether CLAUDE.md / AGENTS.md exist at the root
  - skills / agents       : count of project-level .claude/skills and .claude/agents
  - engram_ns             : engram project namespace (from .engram/config.json)
  - engram_count          : non-deleted engram observations for that namespace
  - summary               : one short line (Goal) from the latest session_summary

Caching keeps the 2s dashboard refresh cheap:
  - cheap filesystem facts recompute only when a watched mtime changes
  - the engram query (sqlite, read-only) recomputes only past a TTL

Privacy: the engram DB is opened READ-ONLY and only a single short line plus a
count are read. Nothing here is ever written back to engram or to the repo.

CLI: context.py <dir>   -> prints the context as JSON (for debugging).
"""
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")),
    "tmux-ai-session-manager", "ctx",
)
ENGRAM_DB = os.path.join(HOME, ".engram", "engram.db")


def _tmux_opt(name, default):
    try:
        out = subprocess.run(
            ["tmux", "show-option", "-gqv", name],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        return out if out else default
    except Exception:
        return default


TTL = float(_tmux_opt("@ai_ctx_ttl", "60") or "60")


def _hash(cwd):
    # Stable cache key; mirrors the spirit of helpers.sh session_hash.
    return hashlib.md5((cwd + "\n").encode("utf-8")).hexdigest()[:8]


def _mtime(path):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return 0.0


def _count_dir(path, suffix=None):
    try:
        entries = os.listdir(path)
    except OSError:
        return 0
    if suffix:
        return sum(1 for e in entries if e.endswith(suffix))
    return sum(1 for e in entries if not e.startswith("."))


def _watched_mtimes(cwd):
    return {
        "claude_md": _mtime(os.path.join(cwd, "CLAUDE.md")),
        "agents_md": _mtime(os.path.join(cwd, "AGENTS.md")),
        "skills": _mtime(os.path.join(cwd, ".claude", "skills")),
        "agents": _mtime(os.path.join(cwd, ".claude", "agents")),
        "engram_cfg": _mtime(os.path.join(cwd, ".engram", "config.json")),
    }


def _compute_cheap(cwd):
    return {
        "claude_md": os.path.isfile(os.path.join(cwd, "CLAUDE.md")),
        "agents_md": os.path.isfile(os.path.join(cwd, "AGENTS.md")),
        "skills": _count_dir(os.path.join(cwd, ".claude", "skills")),
        "agents": _count_dir(os.path.join(cwd, ".claude", "agents"), suffix=".md"),
    }


def _engram_ns(cwd):
    cfg = os.path.join(cwd, ".engram", "config.json")
    try:
        with open(cfg) as fh:
            return json.load(fh).get("project_name") or None
    except Exception:
        return None


def _goal_line(content):
    """Extract a short line from a session_summary markdown body."""
    if not content:
        return ""
    lines = content.splitlines()
    # Prefer the first non-empty line under "## Goal".
    for i, ln in enumerate(lines):
        if ln.strip().lower().startswith("## goal"):
            for nxt in lines[i + 1:]:
                if nxt.strip():
                    return nxt.strip()
            break
    # Fallback: first non-empty, non-heading line.
    for ln in lines:
        s = ln.strip()
        if s and not s.startswith("#"):
            return s
    return ""


def _compute_engram(ns):
    result = {"engram_ns": ns, "engram_count": 0, "summary": ""}
    if not ns or not os.path.isfile(ENGRAM_DB):
        return result
    try:
        con = sqlite3.connect(f"file:{ENGRAM_DB}?mode=ro", uri=True, timeout=1.0)
        con.execute("PRAGMA busy_timeout=500")
        cur = con.cursor()
        (count,) = cur.execute(
            "SELECT count(*) FROM observations WHERE project=? AND deleted_at IS NULL",
            (ns,),
        ).fetchone()
        result["engram_count"] = count
        row = cur.execute(
            "SELECT content FROM observations "
            "WHERE project=? AND type='session_summary' AND deleted_at IS NULL "
            "ORDER BY created_at DESC LIMIT 1",
            (ns,),
        ).fetchone()
        if row:
            result["summary"] = _goal_line(row[0])
        con.close()
    except Exception:
        pass
    return result


def get_context(cwd):
    """Return the context dict for a project dir, using/refreshing the cache."""
    if cwd.startswith("~"):
        cwd = HOME + cwd[1:]
    now = time.time()
    key = _hash(cwd)
    cache_file = os.path.join(CACHE_DIR, key + ".json")

    cached = None
    try:
        with open(cache_file) as fh:
            cached = json.load(fh)
    except Exception:
        cached = None

    mt = _watched_mtimes(cwd)
    data = dict(cached) if cached else {}

    # Cheap facts: recompute when a watched mtime changed (or no cache).
    if not cached or cached.get("_mtimes") != mt:
        data.update(_compute_cheap(cwd))
        data["_mtimes"] = mt
        # config.json changed -> namespace may have changed; force engram refresh.
        data["_engram_at"] = 0

    # Engram: recompute past TTL.
    if not cached or (now - data.get("_engram_at", 0)) > TTL:
        ns = _engram_ns(cwd)
        data.update(_compute_engram(ns))
        data["_engram_at"] = now

    data["cwd"] = cwd
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = cache_file + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(data, fh)
        os.replace(tmp, cache_file)
    except Exception:
        pass
    return data


def format_line(ctx):
    """One human-readable line: badges + summary. Used by the picker preview."""
    badges = []
    if ctx.get("claude_md"):
        badges.append("CLAUDE.md")
    if ctx.get("agents_md"):
        badges.append("AGENTS.md")
    if ctx.get("skills"):
        badges.append(f"{ctx['skills']} skills")
    if ctx.get("agents"):
        badges.append(f"{ctx['agents']} agents")
    if ctx.get("engram_count"):
        badges.append(f"{ctx['engram_count']} memorias")
    out = []
    if badges:
        out.append(" · ".join(badges))
    if ctx.get("summary"):
        out.append("↳ " + ctx["summary"])
    return "\n".join(out)


def format_row(ctx, maxlen=60):
    """Single compact line for a picker row: summary if any, else badges."""
    summary = (ctx.get("summary") or "").strip().replace("\t", " ")
    if summary:
        if len(summary) > maxlen:
            summary = summary[: maxlen - 1] + "…"
        return "↳ " + summary
    badges = []
    if ctx.get("claude_md"):
        badges.append("C")
    if ctx.get("agents_md"):
        badges.append("A")
    if ctx.get("skills"):
        badges.append(f"sk:{ctx['skills']}")
    if ctx.get("agents"):
        badges.append(f"ag:{ctx['agents']}")
    if ctx.get("engram_count"):
        badges.append(f"eng:{ctx['engram_count']}")
    return " ".join(badges)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--row":
        print(format_row(get_context(sys.argv[2])))
    elif len(sys.argv) > 2 and sys.argv[1] == "--line":
        print(format_line(get_context(sys.argv[2])))
    else:
        target = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
        print(json.dumps(get_context(target), indent=2, ensure_ascii=False))
