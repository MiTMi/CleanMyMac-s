"""Install/remove claude-guard hooks in ~/.claude/settings.json and the LaunchAgent."""
import json
import os
import shutil
import subprocess
import sys
import time

from .discover import claude_dir, watch_paths
from .model import GUARD_HOME

MARK = "claude-guard"
LABEL = "com.claude-guard.watch"
PLIST = os.path.expanduser("~/Library/LaunchAgents/%s.plist" % LABEL)


def _settings_path():
    return os.path.join(claude_dir(), "settings.json")


def _load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    return json.loads(txt) if txt.strip() else {}


def _strip(hooks):
    for ev in list(hooks):
        groups = []
        for g in hooks[ev] if isinstance(hooks[ev], list) else []:
            hs = [h for h in g.get("hooks", []) if MARK not in json.dumps(h)]
            if hs:
                g["hooks"] = hs
                groups.append(g)
        if groups:
            hooks[ev] = groups
        else:
            hooks.pop(ev)


def install_hooks(py, guard):
    path = _settings_path()
    try:
        data = _load(path)
    except ValueError as e:
        raise SystemExit("~/.claude/settings.json is not valid JSON (%s) - fix it first." % e)
    if os.path.exists(path):
        bdir = os.path.join(GUARD_HOME, "backups")
        os.makedirs(bdir, exist_ok=True)
        shutil.copy2(path, os.path.join(bdir, "settings.json.%s" % time.strftime("%Y%m%d-%H%M%S")))
    hooks = data.setdefault("hooks", {})
    _strip(hooks)
    base = '"%s" "%s" hook ' % (py, guard)
    hooks.setdefault("SessionStart", []).append({
        "matcher": "startup|resume|clear",
        "hooks": [{"type": "command", "command": base + "session-start", "timeout": 60}]})
    hooks.setdefault("PreToolUse", []).append({
        "matcher": "^(Bash|Write|Edit|MultiEdit|Skill)$|^mcp__",
        "hooks": [{"type": "command", "command": base + "pre-tool-use", "timeout": 90}]})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".cg-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    if data.get("disableAllHooks") is True:
        print("WARNING: disableAllHooks=true in settings.json - hooks will not run.")
    return path


def uninstall_hooks():
    path = _settings_path()
    if not os.path.exists(path):
        return
    data = _load(path)
    hooks = data.get("hooks") or {}
    _strip(hooks)
    if not hooks:
        data.pop("hooks", None)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def install_agent(py, guard):
    if sys.platform != "darwin":
        print("(not macOS - LaunchAgent skipped)")
        return None
    paths = [p for p in watch_paths() if os.path.exists(p)]
    items = "".join("    <string>%s</string>\n" % _x(p) for p in paths)
    plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>%s</string>
  <key>ProgramArguments</key>
  <array>
    <string>%s</string>
    <string>%s</string>
    <string>watch-tick</string>
  </array>
  <key>WatchPaths</key>
  <array>
%s  </array>
  <key>StartInterval</key><integer>3600</integer>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>%s</string>
</dict>
</plist>
""" % (LABEL, _x(py), _x(guard), items, _x(os.path.join(GUARD_HOME, "watch.err")))
    os.makedirs(os.path.dirname(PLIST), exist_ok=True)
    uid = str(os.getuid())
    subprocess.call(["launchctl", "bootout", "gui/" + uid, PLIST], stderr=subprocess.DEVNULL)
    with open(PLIST, "w") as f:
        f.write(plist)
    rc = subprocess.call(["launchctl", "bootstrap", "gui/" + uid, PLIST])
    return paths if rc == 0 else None


def uninstall_agent():
    if sys.platform == "darwin" and os.path.exists(PLIST):
        subprocess.call(["launchctl", "bootout", "gui/%d" % os.getuid(), PLIST], stderr=subprocess.DEVNULL)
        os.remove(PLIST)


def _x(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ------------------------------------------------------------------ repo mode
REPO_DIR = os.path.join(".claude", "claude-guard")


def repo_hook_cmd(event, everywhere):
    gate = "" if everywhere else '[ "$CLAUDE_CODE_REMOTE" = "true" ] || exit 0; '
    return gate + 'python3 "$CLAUDE_PROJECT_DIR/.claude/claude-guard/guard.py" hook ' + event


def install_repo(repo, src, everywhere=False):
    repo = os.path.abspath(os.path.expanduser(repo))
    if not os.path.isdir(repo):
        raise SystemExit("not a directory: " + repo)
    dest = os.path.join(repo, REPO_DIR)
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    shutil.copy2(os.path.join(src, "guard.py"), dest)
    shutil.copytree(os.path.join(src, "cg"), os.path.join(dest, "cg"),
                    ignore=shutil.ignore_patterns("__pycache__"))
    with open(os.path.join(src, "skill", "SKILL.md"), encoding="utf-8") as f:
        skill = f.read().replace("~/.claude-guard/bin/claude-guard", "python3 .claude/claude-guard/guard.py").replace(
            "status --no-projects", "status")
    sk = os.path.join(repo, ".claude", "skills", "claude-guard")
    os.makedirs(sk, exist_ok=True)
    with open(os.path.join(sk, "SKILL.md"), "w", encoding="utf-8") as f:
        f.write(skill)
    path = os.path.join(repo, ".claude", "settings.json")
    data = _load(path)
    hooks = data.setdefault("hooks", {})
    _strip(hooks)
    hooks.setdefault("SessionStart", []).append({
        "matcher": "startup|resume|clear",
        "hooks": [{"type": "command", "command": repo_hook_cmd("session-start", everywhere), "timeout": 60}]})
    hooks.setdefault("PreToolUse", []).append({
        "matcher": "^(Bash|Write|Edit|MultiEdit|Skill)$|^mcp__",
        "hooks": [{"type": "command", "command": repo_hook_cmd("pre-tool-use", everywhere), "timeout": 90}]})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    return [os.path.relpath(p, repo) for p in (dest, sk, path)]


def uninstall_repo(repo):
    repo = os.path.abspath(os.path.expanduser(repo))
    shutil.rmtree(os.path.join(repo, REPO_DIR), ignore_errors=True)
    shutil.rmtree(os.path.join(repo, ".claude", "skills", "claude-guard"), ignore_errors=True)
    path = os.path.join(repo, ".claude", "settings.json")
    if os.path.exists(path):
        data = _load(path)
        _strip(data.get("hooks") or {})
        if not data.get("hooks"):
            data.pop("hooks", None)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
