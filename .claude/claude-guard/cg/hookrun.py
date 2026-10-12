"""PreToolUse gate + launchd watcher."""
import json
import os
import re
import subprocess
import sys
import time

from . import engine
from .checks import mcp_config_checks, resolve_package, settings_checks
from .hooks import _emit, _summ, install_targets, effective_command, SENSITIVE_PATH, BUDGET
from .model import Result, Component, GUARD_HOME, short_path
from .scan import scan_text, skill_checks


MAC_ONLY = {"PERSIST-LAUNCHD", "PERSIST-API", "GATEKEEPER", "CRED-KEYCHAIN", "KEYCHAIN-API",
            "OSASCRIPT-PHISH", "CLIPBOARD-SCREEN", "CRED-BROWSER"}


def _decision(results, what):
    worst = max([r.worst for r in results] or [-1])
    lines = _summ(results)
    if worst >= 4:
        return {"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": "claude-guard blocked %s - DANGEROUS findings:\n%s\n"
            "If you are sure, review with `claude-guard check` and run it yourself."
            % (what, "\n".join(lines))}}
    if worst >= 3:
        return {"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "ask",
            "permissionDecisionReason": "claude-guard: %s looks SUSPICIOUS:\n%s" % (what, "\n".join(lines))}}
    if worst >= 2:
        return {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": "claude-guard pre-install check for %s: CAUTION - %s"
            % (what, " | ".join(lines))}}
    return None


def _quarantine_hit(tool, tin):
    q = engine.quarantined()
    if not q:
        return None
    names = {}
    for cid, info in q:
        names.setdefault(info.get("kind"), {})[info.get("name")] = cid
    if tool.startswith("mcp__"):
        server = tool[5:].split("__", 1)[0]
        for n, cid in (names.get("mcp") or {}).items():
            if server == n or re.sub(r"[^A-Za-z0-9_-]", "_", n) == server or server.endswith("_" + n):
                return cid
        for n, cid in (names.get("plugin") or {}).items():
            if server.startswith("plugin_%s_" % n):
                return cid
    if tool == "Skill":
        s = str(tin.get("skill") or tin.get("command") or tin.get("name") or "").lstrip("/")
        s = s.split()[0] if s else s
        for kind in ("skill", "command"):
            for n, cid in (names.get(kind) or {}).items():
                if s and (s == n or s.split(":")[-1] == n or s == n.rsplit(".", 1)[0]):
                    return cid
    return None


def _write_checks(path, tin):
    content = tin.get("content")
    if content is None:
        parts = [tin.get("new_string") or ""] + [e.get("new_string", "") for e in tin.get("edits") or []
                                                if isinstance(e, dict)]
        content = "\n".join(parts)
    if not content:
        return []
    out, extra = [], []
    low = path.lower()
    project = not path.startswith(os.path.join(os.path.expanduser("~"), ".claude") + os.sep) and \
        "claude_desktop_config" not in low and not low.endswith("/.claude.json")
    if low.endswith(".json"):
        try:
            data = json.loads(content)
        except ValueError:
            data = None
        if isinstance(data, dict):
            if "settings" in os.path.basename(low):
                out += settings_checks(data, path, project_scope=project)
            servers = data.get("mcpServers")
            if isinstance(servers, dict):
                from .targets import check_mcp_config
                for n, cfg in list(servers.items())[:5]:
                    if isinstance(cfg, dict):
                        extra += check_mcp_config(cfg, n)
        else:
            scan_text(content, "config", path, findings=out)
    elif low.endswith((".md", ".mdx", ".txt")):
        scan_text(content, "instr", path, findings=out)
        skill_checks(content, path, out)
    elif low.endswith((".js", ".mjs", ".ts", ".py")):
        scan_text(content, "code", path, findings=out)
    else:
        scan_text(content, "shell", path, findings=out)
    return [Result(Component("file", os.path.basename(path), path), out)] + extra


def pre_tool_use(inp):
    tool = inp.get("tool_name") or ""
    tin = inp.get("tool_input") or {}
    hit = _quarantine_hit(tool, tin)
    if hit:
        _emit({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": "claude-guard: %s is flagged DANGEROUS and not trusted. "
            "Review with `claude-guard status`; if it is a false positive run "
            "`claude-guard trust %s`." % (hit, hit)}})
        return
    results, what = [], ""
    t0 = time.time()
    if tool == "Bash":
        cmd = tin.get("command") or ""
        what = "this command"
        own = Result(Component("command", "bash", "Bash"),
                     scan_text(effective_command(cmd), "shell", "Bash command"))
        if sys.platform != "darwin":   # e.g. a Linux cloud session: macOS-only techniques can't run there
            own.findings = [f for f in own.findings if f.rule not in MAC_ONLY]
        own.findings = [f for f in own.findings if f.level >= 3]
        results.append(own)
        for label, job in install_targets(cmd):
            if time.time() - t0 > BUDGET:
                break
            what = label
            try:
                results += job()
            except Exception as e:
                sys.stderr.write("claude-guard: check failed for %s: %s\n" % (label, e))
    elif tool in ("Write", "Edit", "MultiEdit"):
        path = os.path.abspath(os.path.expanduser(tin.get("file_path") or ""))
        if not SENSITIVE_PATH.search(path):
            return
        what = "this write to " + short_path(path)
        results = _write_checks(path, tin)
    if results:
        d = _decision(results, what)
        if d:
            _emit(d)


# ------------------------------------------------------------- launchd tick
def notify(title, msg):
    if sys.platform != "darwin":
        sys.stderr.write("%s: %s\n" % (title, msg))
        return
    esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
    subprocess.call(["osascript", "-e", 'display notification "%s" with title "%s" sound name "Basso"'
                     % (esc(msg[:220]), esc(title))], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def watch_tick():
    time.sleep(float(os.environ.get("CLAUDE_GUARD_SETTLE", "4")))
    lock = os.path.join(GUARD_HOME, "watch.lock")
    try:
        if time.time() - os.path.getmtime(lock) < 120:
            return
    except OSError:
        pass
    os.makedirs(GUARD_HOME, exist_ok=True)
    open(lock, "w").close()
    try:
        changed, removed, total = engine.drift(projects=False)
    finally:
        try:
            os.remove(lock)
        except OSError:
            pass
    if not changed:
        return
    from .report import render
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with open(os.path.join(GUARD_HOME, "last-report.txt"), "w") as f:
        f.write("claude-guard report %s\n\n" % stamp + render(changed, color=False) + "\n")
    with open(os.path.join(GUARD_HOME, "history.log"), "a") as f:
        for r in changed:
            f.write("%s\t%s\t%s\t%s\n" % (stamp, r.meta.get("change"), r.verdict, r.component.id))
    bad = [r for r in changed if r.worst >= 3]
    if bad:
        for r in sorted(bad, key=lambda r: -r.worst)[:3]:
            top = sorted(r.active, key=lambda f: -f.level)[0]
            notify("Claude Guard: %s" % r.verdict,
                   "%s '%s' (%s): %s. Run: claude-guard status" % (r.component.kind, r.component.name,
                                                                  r.meta.get("change"), top.title))
    else:
        new = [r for r in changed if r.meta.get("change") == "new" and r.component.kind in
               ("mcp", "extension", "skill", "plugin", "agent", "command")]
        if new and os.environ.get("CLAUDE_GUARD_QUIET") != "1":
            names = ", ".join("%s '%s'" % (r.component.kind, r.component.name) for r in new[:3])
            notify("Claude Guard: new install scanned", "%s%s - no high-risk findings" %
                   (names, " +%d more" % (len(new) - 3) if len(new) > 3 else ""))
