"""Disable a flagged component (reversible)."""
import json
import os
import shutil
import time

from .discover import discover_all
from .model import GUARD_HOME, short_path

QDIR = os.path.join(GUARD_HOME, "quarantine")


def find(cid):
    comps = discover_all(True)
    exact = [c for c in comps if c.id == cid]
    if exact:
        return exact[0], []
    loose = [c for c in comps if c.name == cid or c.id.startswith(cid + "@")]
    return (loose[0], []) if len(loose) == 1 else (None, [c.id for c in loose])


def quarantine(cid):
    c, amb = find(cid)
    if not c:
        return False, "Not found%s" % (": ambiguous " + ", ".join(amb) if amb else "")
    os.makedirs(QDIR, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    safe = "".join(ch if ch.isalnum() or ch in "-_." else "_" for ch in c.id)
    if c.kind in ("skill", "agent", "command", "workflow", "output-style", "rule", "hook-scripts") and c.root:
        dest = os.path.join(QDIR, "%s-%s" % (stamp, safe))
        shutil.move(c.root, dest)
        _log(stamp, c.id, "moved %s -> %s" % (c.root, dest))
        return True, "Moved %s to %s (move it back to restore)." % (short_path(c.root), short_path(dest))
    if c.kind == "mcp" and c.source.endswith(("claude_desktop_config.json", ".claude.json", ".mcp.json")) \
            and not c.scope.endswith("(local)"):
        with open(c.source, encoding="utf-8") as f:
            data = json.load(f)
        servers = data.get("mcpServers") or {}
        if c.name not in servers:
            return False, "Server not found in " + short_path(c.source)
        backup = os.path.join(QDIR, "%s-%s.backup.json" % (stamp, os.path.basename(c.source)))
        shutil.copy2(c.source, backup)
        removed = servers.pop(c.name)
        with open(os.path.join(QDIR, "%s-%s.json" % (stamp, safe)), "w") as f:
            json.dump({"source": c.source, "name": c.name, "config": removed}, f, indent=2)
        tmp = c.source + ".cg-tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, c.source)
        _log(stamp, c.id, "removed from %s (backup %s)" % (c.source, backup))
        extra = " Restart Claude Desktop." if "claude_desktop_config" in c.source else ""
        return True, "Removed MCP '%s' from %s. Backup: %s.%s" % (c.name, short_path(c.source),
                                                                   short_path(backup), extra)
    if c.kind == "plugin":
        return False, "Run: claude plugin disable %s   (or /plugin in Claude Code)" % c.name
    if c.kind == "extension":
        return False, "Claude Desktop -> Settings -> Extensions -> %s -> Uninstall" % c.name
    return False, "Automatic quarantine not supported for %s; remove it manually: %s" % (
        c.kind, short_path(c.source))


def _log(stamp, cid, msg):
    with open(os.path.join(QDIR, "log.txt"), "a") as f:
        f.write("%s\t%s\t%s\n" % (stamp, cid, msg))
