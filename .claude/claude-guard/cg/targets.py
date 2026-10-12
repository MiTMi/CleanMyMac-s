"""Turn a user-supplied target (URL, package spec, path, JSON) into scan results."""
import json
import os
import re

from . import net
from .checks import mcp_config_checks, resolve_package, settings_checks, hook_checks
from .model import Component, Finding, Result
from .precheck import check_npm, check_pypi, _age_days
from .scan import scan_tree

GH_RX = re.compile(r"^(?:https?://)?(?:www\.)?github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?"
                   r"(?:/(?:tree|blob)/([^/]+)(/.*)?)?/?$")


def detect_context(root):
    if os.path.isfile(os.path.join(root, "SKILL.md")):
        return "skill"
    if os.path.isdir(os.path.join(root, ".claude-plugin")):
        return "plugin"
    if os.path.isfile(os.path.join(root, "manifest.json")):
        return "extension"
    return "package"


def scan_local(root, label=None, depth=0):
    """Scan a directory as whatever it looks like; follow plugin MCP packages."""
    root = os.path.abspath(os.path.expanduser(root))
    ctx = detect_context(root)
    kind = {"package": "repo"}.get(ctx, ctx)
    comp = Component(kind, label or os.path.basename(root.rstrip("/")), root, root, None, "check")
    out = []
    # skills inside a repo: treat each SKILL.md dir as instructions
    _, fp, stats = scan_tree(root, "skill" if ctx == "skill" else ctx, out)
    extras = []
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in ("node_modules", ".git", ".venv", "venv")]
        if "SKILL.md" in files and dirpath != root and ctx != "skill":
            scan_tree(dirpath, "skill", out)
        for fn in files:
            p = os.path.join(dirpath, fn)
            if fn == "hooks.json" or (fn.startswith("settings") and fn.endswith(".json")
                                      and ".claude" in dirpath):
                data = _load(p)
                if isinstance(data, dict):
                    if fn == "hooks.json":
                        hook_checks(data.get("hooks", data), p, out, project_scope=True)
                    else:
                        out += settings_checks(data, p, project_scope=True)
            elif fn in (".mcp.json", "plugin.json", "manifest.json") or fn.endswith("mcp.json"):
                data = _load(p) or {}
                servers = data.get("mcpServers") if isinstance(data, dict) else None
                if fn == "manifest.json" and isinstance(data, dict):
                    mc = (data.get("server") or {}).get("mcp_config")
                    servers = {"server": mc} if isinstance(mc, dict) else None
                if isinstance(servers, dict):
                    for sname, cfg in servers.items():
                        if isinstance(cfg, dict):
                            out += mcp_config_checks(cfg, p)
                            pkg = resolve_package(cfg)
                            if pkg and depth == 0 and pkg[0] in ("npm", "pypi"):
                                extras.append(check_npm(pkg[1], pkg[2]) if pkg[0] == "npm"
                                              else check_pypi(pkg[1], pkg[2]))
    from .engine import _dedupe
    from .precheck import relativize
    from .enrich import enrich_tree
    out += enrich_tree(root, "skill" if ctx == "skill" else ctx)
    out = _dedupe(out)
    relativize(out, root, label or os.path.basename(root.rstrip("/")))
    return [Result(comp, out, fp, {"context": ctx, "files": stats["files"]})] + extras


def _load(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def check_github(owner, repo, ref=None, sub=None):
    src = "github:%s/%s" % (owner, repo)
    meta, pre = {}, []
    try:
        info = net.get_json("https://api.github.com/repos/%s/%s" % (owner, repo))
        meta = {"stars": info.get("stargazers_count"), "created": info.get("created_at"),
                "pushed": info.get("pushed_at"), "archived": info.get("archived"),
                "fork": info.get("fork"), "owner_type": (info.get("owner") or {}).get("type")}
        ref = ref or info.get("default_branch")
        age = _age_days(info.get("created_at") or "")
        if age is not None and age < 30:
            pre.append(Finding("NEW-REPO", "MEDIUM", "Repository created %.0f days ago" % age, src, 0, "", ""))
        if (info.get("stargazers_count") or 0) < 5:
            pre.append(Finding("LOW-ADOPTION", "LOW", "Fewer than 5 stars", src, 0, "", ""))
        if info.get("archived"):
            pre.append(Finding("ARCHIVED", "LOW", "Repository is archived (no security fixes)", src, 0, "", ""))
    except net.NetError as e:
        pre.append(Finding("GH-META", "INFO", "GitHub metadata unavailable", src, 0, str(e)[:150], ""))
    url = "https://codeload.github.com/%s/%s/tar.gz/%s" % (owner, repo, ref or "HEAD")
    wd = net.workdir()
    try:
        try:
            blob = net.get(url, accept="*/*")
        except net.NetError:
            url = "https://api.github.com/repos/%s/%s/tarball/%s" % (owner, repo, ref or "")
            blob = net.get(url.rstrip("/"), accept="*/*")
        warns = net.extract(blob, wd, url)
        root = net.single_subdir(wd)
        if sub:
            cand = os.path.join(root, sub.strip("/"))
            if os.path.exists(cand):
                root = cand
        results = scan_local(root, "%s/%s%s" % (owner, repo, sub or ""))
        results[0].component.source = src + ("@" + ref if ref else "") + (sub or "")
        results[0].component.root = None
        results[0].findings = pre + [Finding("ARCHIVE", "MEDIUM", "Archive warning", src, 0, w, "")
                                     for w in warns] + results[0].findings
        results[0].meta.update(meta)
        return results
    except net.NetError as e:
        return [Result(Component("repo", "%s/%s" % (owner, repo), src), pre + [
            Finding("DOWNLOAD-FAILED", "HIGH", "Could not download repository", src, 0, str(e)[:150],
                    "Unverified - do not install blind.")], meta=meta)]
    finally:
        net.cleanup(wd)


def check_archive_bytes(data, label):
    wd = net.workdir()
    try:
        from .enrich import enrich_bytes
        warns = net.extract(data, wd, label)
        res = scan_local(net.single_subdir(wd), label)
        res[0].findings = enrich_bytes(data, label) + res[0].findings
        res[0].findings = [Finding("ARCHIVE", "MEDIUM", "Archive warning", label, 0, w, "")
                           for w in warns] + res[0].findings
        res[0].component.root = None
        return res
    finally:
        net.cleanup(wd)


def check_mcp_config(cfg, name="server"):
    src = "config:" + name
    comp = Component("mcp", name, src, None, cfg, "check")
    out = mcp_config_checks(cfg, src)
    if cfg.get("url"):
        from .enrich import enrich_url
        out += enrich_url(cfg["url"], src)
    results = [Result(comp, out)]
    pkg = resolve_package(cfg)
    if pkg and pkg[0] == "npm":
        results.append(check_npm(pkg[1], pkg[2]))
    elif pkg and pkg[0] == "pypi":
        results.append(check_pypi(pkg[1], pkg[2]))
    return results


def check_target(t):
    """Dispatch on the target string."""
    t = t.strip()
    if t.startswith("{"):
        data = json.loads(t)
        servers = data.get("mcpServers", data if "command" not in data and "url" not in data else {"server": data})
        res = []
        for n, c in servers.items():
            res += check_mcp_config(c, n)
        return res
    m = re.match(r"^(npm|pypi|pip|github|gh):(.+)$", t)
    if m:
        eco, spec = m.group(1), m.group(2)
        if eco in ("github", "gh"):
            return check_target("https://github.com/" + spec.replace("@", "/tree/", 1)
                                if "@" in spec and "/tree/" not in spec else "https://github.com/" + spec)
        if eco == "npm":
            if spec.startswith("@"):
                n, _, v = spec[1:].partition("@")
                return [check_npm("@" + n, v or None)]
            n, _, v = spec.partition("@")
            return [check_npm(n, v or None)]
        n, _, v = spec.partition("==")
        return [check_pypi(n, v or None)]
    g = GH_RX.match(t)
    if g:
        return check_github(g.group(1), g.group(2), g.group(3), g.group(4))
    m = re.match(r"^https?://(www\.)?npmjs\.com/package/((@[^/]+/)?[^/?#]+)(/v/([^/?#]+))?", t)
    if m:
        return [check_npm(m.group(2), m.group(5))]
    m = re.match(r"^https?://pypi\.org/project/([^/?#]+)/?([^/?#]+)?", t)
    if m:
        return [check_pypi(m.group(1), m.group(2))]
    if re.match(r"^https?://", t):
        if re.search(r"\.(zip|mcpb|dxt|skill|plugin|tgz|tar\.gz|tar)(\?|$)", t):
            return check_archive_bytes(net.get(t, accept="*/*"), t)
        return check_mcp_config({"type": "http", "url": t}, t)
    p = os.path.expanduser(t)
    if os.path.isdir(p):
        return scan_local(p)
    if os.path.isfile(p):
        if p.endswith((".zip", ".mcpb", ".dxt", ".skill", ".plugin", ".tgz", ".gz", ".tar")):
            with open(p, "rb") as f:
                return check_archive_bytes(f.read(), os.path.basename(p))
        if p.endswith(".json"):
            data = _load(p) or {}
            if isinstance(data, dict) and isinstance(data.get("mcpServers"), dict):
                res = []
                for n, c in data["mcpServers"].items():
                    res += check_mcp_config(c, n)
                return res
        return scan_local(p)
    # bare name: guess npm
    if re.match(r"^(@[\w.-]+/)?[\w.-]+(@[\w.^~-]+)?$", t):
        return check_target("npm:" + t)
    raise ValueError("Don't know how to check %r" % t)
