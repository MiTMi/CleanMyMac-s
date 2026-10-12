"""Discover everything that can put code or instructions in front of Claude
on this Mac: Claude Desktop (MCP config, Desktop Extensions, Cowork/desktop
skills & plugins) and Claude Code (user/project/managed scopes)."""
import glob
import json
import os
import sys

from .model import Component

H = os.path.expanduser("~")


def _p(*a):
    return os.path.join(*a)


def desktop_dir():
    if os.environ.get("CLAUDE_GUARD_DESKTOP_DIR"):
        return os.environ["CLAUDE_GUARD_DESKTOP_DIR"]
    if sys.platform == "darwin":
        return _p(H, "Library", "Application Support", "Claude")
    if os.name == "nt":
        return _p(os.environ.get("APPDATA", H), "Claude")
    return _p(H, ".config", "Claude")


def claude_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or _p(H, ".claude")


def managed_dir():
    if sys.platform == "darwin":
        return "/Library/Application Support/ClaudeCode"
    return "/etc/claude-code"


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def watch_paths():
    """Paths whose change means 'something was installed'."""
    d, c = desktop_dir(), claude_dir()
    return [_p(d, "claude_desktop_config.json"), _p(d, "Claude Extensions"),
            _p(c, "skills"), _p(c, "agents"), _p(c, "commands"), _p(c, "settings.json"),
            _p(c, "plugins", "installed_plugins.json")]


# --------------------------------------------------------------- MCP helpers
def mcp_components(servers, source, scope, out):
    if not isinstance(servers, dict):
        return
    for name, cfg in servers.items():
        if isinstance(cfg, dict):
            out.append(Component("mcp", name, source, _local_root(cfg), cfg, scope))


def _local_root(cfg):
    """If an MCP server runs a local script, return the project dir to scan."""
    cmd = cfg.get("command") or ""
    args = [a for a in (cfg.get("args") or []) if isinstance(a, str)]
    cands = [cmd] + args
    for c in cands:
        c = os.path.expanduser(c)
        if os.path.isabs(c) and os.path.isfile(c) and not c.startswith(("/usr/", "/bin/",
                                                                      "/opt/homebrew/bin",
                                                                      "/usr/local/bin")):
            d = os.path.dirname(c)
            for _ in range(4):   # climb to the package root
                if any(os.path.exists(_p(d, m)) for m in ("package.json", "pyproject.toml",
                                                          "setup.py", "manifest.json", ".git")):
                    return d
                parent = os.path.dirname(d)
                if parent == d or parent in (H, "/"):
                    break
                d = parent
            return os.path.dirname(c)
        if os.path.isabs(c) and os.path.isdir(c) and cands.index(c) > 0 and "--directory" in args:
            return c
    if "--directory" in args:
        i = args.index("--directory")
        if i + 1 < len(args) and os.path.isdir(os.path.expanduser(args[i + 1])):
            return os.path.expanduser(args[i + 1])
    return None


# ------------------------------------------------------------ Claude Desktop
SKIP_DESKTOP = {"Cache", "Code Cache", "GPUCache", "IndexedDB", "Local Storage",
                "Session Storage", "Service Worker", "blob_storage", "Crashpad", "logs",
                "Partitions", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
                "Shared Dictionary", "WebStorage", "sentry", "Claude Extensions",
                "vm_bundles", "claude-code", "claude-code-vm", "node_modules", ".git",
                "marketplaces"}   # marketplace clones are catalogs, not installed plugins


def discover_desktop(out):
    d = desktop_dir()
    cfg_path = _p(d, "claude_desktop_config.json")
    cfg = load_json(cfg_path) or {}
    mcp_components(cfg.get("mcpServers"), cfg_path, "desktop", out)

    ext_root = _p(d, "Claude Extensions")
    settings_root = _p(d, "Claude Extensions Settings")
    for mf in sorted(glob.glob(_p(ext_root, "*", "manifest.json"))):
        edir = os.path.dirname(mf)
        man = load_json(mf) or {}
        eid = os.path.basename(edir)
        st = load_json(_p(settings_root, eid + ".json")) or {}
        server = (man.get("server") or {}).get("mcp_config") or {}
        out.append(Component("extension", man.get("name") or eid, mf, edir, server,
                             "desktop", {"id": eid, "version": man.get("version"),
                                         "author": (man.get("author") or {}).get("name"),
                                         "enabled": st.get("isEnabled", True),
                                         "manifest_tools": man.get("tools") or []}))

    # Skills / plugins stored by the desktop app (Cowork, synced, uploaded)
    seen = {}
    for root, dirs, files in os.walk(d):
        dirs[:] = [x for x in dirs if x not in SKIP_DESKTOP]
        if root.count(os.sep) - d.count(os.sep) > 9:
            dirs[:] = []
            continue
        if ".claude-plugin" in dirs and os.path.isfile(_p(root, ".claude-plugin", "plugin.json")):
            man = load_json(_p(root, ".claude-plugin", "plugin.json")) or {}
            name = man.get("name") or os.path.basename(root)
            _keep_newest(seen, ("plugin", name), Component("plugin", name, _p(root, ".claude-plugin", "plugin.json"),
                                                            root, man, "desktop"))
            dirs[:] = []          # its skills are scanned as part of the plugin
        elif "SKILL.md" in files:
            name = os.path.basename(root)
            _keep_newest(seen, ("skill", name), Component("skill", name, _p(root, "SKILL.md"),
                                                           root, None, "desktop"))
            dirs[:] = []
    out.extend(seen.values())


def _keep_newest(seen, key, comp):
    old = seen.get(key)
    try:
        mt = os.path.getmtime(comp.source)
    except OSError:
        mt = 0
    if old is None or mt > old.extra.get("_mtime", 0):
        comp.extra["_mtime"] = mt
        seen[key] = comp


# --------------------------------------------------------------- Claude Code
def discover_dot_claude(base, scope, out):
    """skills/agents/commands/... under a .claude directory."""
    for sk in sorted(glob.glob(_p(base, "skills", "*", "SKILL.md"))):
        root = os.path.dirname(sk)
        out.append(Component("skill", os.path.basename(root), sk, root, None, scope))
    for kind, sub, pat in (("agent", "agents", "**/*.md"), ("command", "commands", "**/*.md"),
                           ("output-style", "output-styles", "*.md"),
                           ("workflow", "workflows", "*.js"), ("rule", "rules", "**/*.md")):
        for f in sorted(glob.glob(_p(base, sub, pat), recursive=True)):
            name = os.path.relpath(f, _p(base, sub))
            out.append(Component(kind, name, f, f, None, scope))
    hooks_dir = _p(base, "hooks")
    if os.path.isdir(hooks_dir):
        out.append(Component("hook-scripts", "hooks", hooks_dir, hooks_dir, None, scope))
    for fn in ("settings.json", "settings.local.json"):
        sp = _p(base, fn)
        data = load_json(sp)
        if isinstance(data, dict):
            out.append(Component("settings", fn, sp, None, data, scope))


def discover_code(out, projects=True):
    c = claude_dir()
    discover_dot_claude(c, "code-user", out)
    cm = _p(c, "CLAUDE.md")
    if os.path.isfile(cm):
        out.append(Component("instructions", "CLAUDE.md", cm, cm, None, "code-user"))

    cj_path = _p(H, ".claude.json")
    cj = load_json(cj_path) or {}
    mcp_components(cj.get("mcpServers"), cj_path, "code-user", out)

    for mp in ("managed-settings.json", "managed-mcp.json"):
        p = _p(managed_dir(), mp)
        data = load_json(p)
        if isinstance(data, dict):
            if mp == "managed-mcp.json":
                mcp_components(data.get("mcpServers"), p, "managed", out)
            else:
                out.append(Component("settings", mp, p, None, data, "managed"))

    discover_plugins(c, out)

    if not projects:
        return
    proj = dict(cj.get("projects") or {}) if isinstance(cj.get("projects"), dict) else {}
    cur = os.environ.get("CLAUDE_PROJECT_DIR")
    if cur and os.path.isdir(cur) and cur not in proj:
        proj[cur] = {}
    for path, pdata in proj.items():
        if not os.path.isdir(path) or path == H:
            continue
        label = "project:" + os.path.basename(path.rstrip("/"))
        if isinstance(pdata, dict):
            mcp_components(pdata.get("mcpServers"), cj_path, label + "(local)", out)
        mj = _p(path, ".mcp.json")
        data = load_json(mj)
        if isinstance(data, dict):
            mcp_components(data.get("mcpServers"), mj, label, out)
        discover_dot_claude(_p(path, ".claude"), label, out)


def discover_plugins(c, out):
    roots = set()
    ip = load_json(_p(c, "plugins", "installed_plugins.json"))

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ("installPath", "path", "installLocation") and isinstance(v, str):
                    roots.add(os.path.expanduser(v))
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(ip)
    for pj in glob.glob(_p(c, "plugins", "cache", "*", "*", "*", ".claude-plugin", "plugin.json")) + \
            glob.glob(_p(c, "plugins", "cache", "*", "*", ".claude-plugin", "plugin.json")) + \
            glob.glob(_p(c, "plugins", "synced", "*", ".claude-plugin", "plugin.json")) + \
            glob.glob(_p(c, "plugins", "synced", "*", "*", ".claude-plugin", "plugin.json")):
        roots.add(os.path.dirname(os.path.dirname(pj)))
    settings = load_json(_p(c, "settings.json")) or {}
    enabled = settings.get("enabledPlugins") or {}
    seen = {}
    for r in sorted(roots):
        if not os.path.isdir(r):
            continue
        man = load_json(_p(r, ".claude-plugin", "plugin.json")) or {}
        name = man.get("name") or os.path.basename(r)
        comp = Component("plugin", name, _p(r, ".claude-plugin", "plugin.json"), r, man,
                         "code-user")
        comp.extra["enabled"] = any(k.split("@")[0] == name and v for k, v in enabled.items()) \
            if isinstance(enabled, dict) else None
        _keep_newest(seen, name, comp)
    for comp in seen.values():
        out.append(comp)
        plugin_mcps(comp, out)


def plugin_mcps(comp, out):
    r, man = comp.root, comp.config or {}
    scope = "plugin:" + comp.name
    mcp_components(_servers(load_json(_p(r, ".mcp.json"))), _p(r, ".mcp.json"), scope, out)
    inline = man.get("mcpServers")
    items = inline if isinstance(inline, list) else [inline]
    for it in items:
        if isinstance(it, dict):
            mcp_components(_servers(it), comp.source, scope, out)
        elif isinstance(it, str) and it.endswith(".json"):
            mcp_components(_servers(load_json(_p(r, it))), _p(r, it), scope, out)


def _servers(data):
    if not isinstance(data, dict):
        return {}
    if isinstance(data.get("mcpServers"), dict):
        return data["mcpServers"]
    if data and all(isinstance(v, dict) and ("command" in v or "url" in v)
                    for v in data.values()):
        return data
    return {}


def discover_all(projects=True):
    out = []
    discover_desktop(out)
    discover_code(out, projects)
    # expand ${CLAUDE_PLUGIN_ROOT} in plugin MCP configs for local-root detection
    for c in out:
        if c.kind == "mcp" and c.root is None and c.scope.startswith("plugin:"):
            pr = os.path.dirname(c.source) if c.source.endswith(".mcp.json") else \
                os.path.dirname(os.path.dirname(c.source))
            c.extra["plugin_root"] = pr
    uniq, seen = [], set()
    for c in out:
        if c.id in seen:
            continue
        seen.add(c.id)
        uniq.append(c)
    return uniq
