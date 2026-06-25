#!/usr/bin/env python3
"""Optional FirstMate awareness for the cockpit.

Reads the FirstMate backlog (In flight / Queued / Done) and lists active
crew windows (named fm-*). Off by default; the dashboard enables it when
@ai_firstmate is 'on'. The FirstMate directory is configurable via
@ai_firstmate_path (default ~/firstmate) so no personal path is hardcoded.

CLI: firstmate.py [path]  -> prints the parsed structure as JSON.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")


def _backlog(path):
    """Parse backlog.md -> {'in_flight': [...], 'queued': [...], 'done': [...]}."""
    sections = {"in_flight": [], "queued": [], "done": []}
    heading = {"in flight": "in_flight", "queued": "queued", "done": "done"}
    f = os.path.join(path, "data", "backlog.md")
    cur = None
    try:
        with open(f) as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                s = line.strip()
                if s.startswith("## "):
                    cur = heading.get(s[3:].strip().lower())
                    continue
                if cur and (s.startswith("- ") or s.startswith("* ")):
                    sections[cur].append(s[2:].strip())
    except Exception:
        pass
    return sections


def _fm_windows():
    """Active tmux windows named fm-* (FirstMate crew)."""
    try:
        out = subprocess.run(
            ["tmux", "list-windows", "-a", "-F", "#{window_name}"],
            capture_output=True, text=True, timeout=2,
        ).stdout
        return [w for w in out.split() if w.startswith("fm")]
    except Exception:
        return []


def get_firstmate(path=None):
    path = path or os.path.join(HOME, "firstmate")
    if not os.path.isdir(path):
        return None
    b = _backlog(path)
    return {
        "in_flight": b["in_flight"],
        "queued": b["queued"],
        "done": b["done"],
        "windows": _fm_windows(),
    }


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else None
    print(json.dumps(get_firstmate(target), indent=2, ensure_ascii=False))
