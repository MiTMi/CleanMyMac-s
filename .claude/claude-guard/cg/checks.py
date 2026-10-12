"""Configuration-level checks: MCP server definitions, settings/hooks."""
import re
from urllib.parse import urlparse

from .model import Finding
from .scan import scan_text

SECRET_RX = re.compile(r"^(sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|"
                       r"github_pat_[A-Za-z0-9_]{30,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|"
                       r"AIza[0-9A-Za-z_-]{30,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{30,})$")
RUNNERS_NPM = ("npx", "bunx", "pnpx")
RUNNERS_PY = ("uvx", "pipx")
LOCAL_HOSTS = ("localhost", "127.0.0.1", "::1", "0.0.0.0")


def resolve_package(cfg):
    """Return ('npm'|'pypi'|'docker', name, version|None) for an MCP config, or None."""
    cmd = (cfg.get("command") or "").strip()
    args = [a for a in (cfg.get("args") or []) if isinstance(a, str)]
    base = cmd.rsplit("/", 1)[-1]
    if " " in base and not args:              # "npx -y pkg" in a single string
        parts = base.split()
        base, args = parts[0], parts[1:]
    if base in ("pnpm", "yarn", "bun", "npm") and args and args[0] in ("dlx", "x", "exec"):
        base, args = "npx", args[1:]
    if base == "uv" and args[:2] == ["tool", "run"]:
        base, args = "uvx", args[2:]
    if base == "pipx" and args and args[0] == "run":
        args = args[1:]
    if base in RUNNERS_NPM or base in RUNNERS_PY:
        eco = "npm" if base in RUNNERS_NPM else "pypi"
        it = iter(range(len(args)))
        for i in it:
            a = args[i]
            if a in ("-p", "--package", "--from", "--with") and i + 1 < len(args):
                return _split(eco, args[i + 1])
            if a.startswith(("--package=", "--from=")):
                return _split(eco, a.split("=", 1)[1])
            if a.startswith("-"):
                if a in ("--python", "--registry", "--index-url", "--cache"):
                    next(it, None)
                continue
            return _split(eco, a)
    if base == "docker" and "run" in args:
        rest = args[args.index("run") + 1:]
        skip = False
        for a in rest:
            if skip:
                skip = False
                continue
            if a in ("-e", "--env", "-v", "--volume", "--name", "-p", "--network", "--mount",
                     "-w", "--workdir", "--user", "-u", "--entrypoint", "--env-file"):
                skip = True
                continue
            if a.startswith("-"):
                continue
            return ("docker", a, None)
    return None


def _split(eco, spec):
    if eco == "npm":
        if spec.startswith("@"):
            name, _, ver = spec[1:].partition("@")
            return ("npm", "@" + name, ver or None)
        name, _, ver = spec.partition("@")
        return ("npm", name, ver or None)
    m = re.match(r"^([A-Za-z0-9._-]+)(\[[^\]]*\])?\s*(==\s*([^\s,;]+))?", spec)
    if m:
        return ("pypi", m.group(1), m.group(4))
    return ("pypi", spec, None)


def mcp_config_checks(cfg, src):
    out = []
    url = cfg.get("url") or cfg.get("serverUrl")
    if url:
        u = urlparse(url)
        host = (u.hostname or "").lower()
        if u.scheme in ("http", "ws") and host not in LOCAL_HOSTS:
            out.append(Finding("MCP-PLAINTEXT", "MEDIUM", "Remote MCP over unencrypted %s" % u.scheme,
                               src, 0, url, "Traffic (and tokens) can be read/modified in transit."))
        if re.search(r"ngrok|trycloudflare|\d+\.\d+\.\d+\.\d+|webhook\.site|pipedream", host):
            out.append(Finding("MCP-SKETCHY-HOST", "HIGH", "Remote MCP on a tunnel/raw-IP host",
                               src, 0, url, "Ephemeral hosts are common for attacker infrastructure."))
        out.append(Finding("MCP-REMOTE", "INFO", "Remote MCP server (code not inspectable)", src, 0,
                           url, "Only its tool descriptions can be checked: run `probe`."))
    cmd = cfg.get("command") or ""
    args = [a for a in (cfg.get("args") or []) if isinstance(a, str)]
    joined = " ".join([cmd] + args)
    base = cmd.rsplit("/", 1)[-1]
    if base in ("bash", "sh", "zsh", "/bin/sh") or "-c" in args:
        scan_text(joined, "shell", src, findings=out)
    else:
        scan_text(joined, "config", src, findings=out)
    pkg = resolve_package(cfg)
    if pkg and pkg[0] in ("npm", "pypi"):
        if pkg[2] in (None, "latest"):
            out.append(Finding("MCP-UNPINNED", "LOW", "Package version not pinned (%s)" % pkg[1],
                               src, 0, joined[:150],
                               "Every launch pulls whatever was published last - a hijacked "
                               "release reaches you automatically. Pin name@x.y.z."))
    elif pkg and pkg[0] == "docker" and "@sha256:" not in pkg[1]:
        out.append(Finding("MCP-DOCKER-TAG", "LOW", "Docker image not pinned by digest", src, 0,
                           pkg[1], "Tags are mutable."))
    env = cfg.get("env") or {}
    if isinstance(env, dict):
        for k, v in env.items():
            v = str(v)
            line = "%s=%s" % (k, v)
            scan_text(line, "config", src, findings=out)
            if SECRET_RX.match(v.strip()):
                out.append(Finding("PLAINTEXT-SECRET", "LOW", "API token stored in plain text (%s)" % k,
                                   src, 0, "%s=%s..." % (k, v[:6]),
                                   "Readable by any process/MCP that can read this file."))
    return out


DANGEROUS_ALLOW = re.compile(r"^(Bash|Bash\(\s*\*\s*\)|\*|mcp__\*?|mcp__(?:(?!__).)+(__\*)?|WebFetch|Write|Edit)$")


def settings_checks(data, src, project_scope=False):
    out = []
    perms = data.get("permissions") or {}
    if isinstance(perms, dict):
        if perms.get("defaultMode") in ("bypassPermissions",):
            out.append(Finding("SET-BYPASS", "HIGH" if not project_scope else "CRITICAL",
                               "defaultMode is bypassPermissions", src, 0,
                               "permissions.defaultMode=bypassPermissions",
                               "No approval prompts at all; any injected instruction executes."))
        for a in perms.get("allow") or []:
            if isinstance(a, str) and DANGEROUS_ALLOW.match(a.strip()):
                out.append(Finding("SET-BROAD-ALLOW", "MEDIUM" if not project_scope else "HIGH",
                                   "Broad auto-approval rule: %s" % a, src, 0, a,
                                   "Everything matching runs without asking."))
        for d in perms.get("additionalDirectories") or []:
            if isinstance(d, str) and d.rstrip("/") in ("~", "/", "/Users", "$HOME"):
                out.append(Finding("SET-WIDE-DIRS", "MEDIUM", "Grants access to whole home/disk",
                                   src, 0, d, ""))
    for k in ("enableAllProjectMcpServers",):
        if data.get(k) is True:
            out.append(Finding("SET-AUTO-MCP", "MEDIUM", "%s=true" % k, src, 0, k,
                               "Any cloned repo's .mcp.json servers start without approval."))
    if data.get("disableAllHooks") is True:
        out.append(Finding("SET-HOOKS-OFF", "INFO", "disableAllHooks=true (claude-guard hooks off)",
                           src, 0, "", ""))
    env = data.get("env") or {}
    if isinstance(env, dict):
        for k, v in env.items():
            scan_text("%s=%s" % (k, v), "config", src, findings=out)
    for key in ("apiKeyHelper", "awsAuthRefresh", "awsCredentialExport", "otelHeadersHelper"):
        v = data.get(key)
        if isinstance(v, str):
            scan_text(v, "shell", src, findings=out)
    sl = data.get("statusLine") or {}
    if isinstance(sl, dict) and isinstance(sl.get("command"), str):
        scan_text(sl["command"], "shell", src, findings=out)
    hook_checks(data.get("hooks") or {}, src, out, project_scope)
    for name, mk in (data.get("extraKnownMarketplaces") or {}).items() \
            if isinstance(data.get("extraKnownMarketplaces"), dict) else []:
        out.append(Finding("SET-MARKETPLACE", "INFO" if not project_scope else "MEDIUM",
                           "Extra plugin marketplace: %s" % name, src, 0, str(mk)[:150],
                           "Make sure you trust whoever controls it."))
    return out


def hook_checks(hooks, src, out, project_scope=False):
    if not isinstance(hooks, dict):
        return
    for event, groups in hooks.items():
        for g in groups if isinstance(groups, list) else []:
            for h in (g.get("hooks") or []) if isinstance(g, dict) else []:
                if not isinstance(h, dict):
                    continue
                t = h.get("type", "command")
                if t == "http":
                    host = (urlparse(h.get("url", "")).hostname or "").lower()
                    if host not in LOCAL_HOSTS:
                        out.append(Finding("HOOK-HTTP-REMOTE", "HIGH",
                                           "%s hook POSTs session data to %s" % (event, host),
                                           src, 0, h.get("url", "")[:150],
                                           "Every matching event (incl. tool inputs) leaves your Mac."))
                elif t == "command":
                    cmd = " ".join([str(h.get("command", ""))] + [str(a) for a in h.get("args") or []])
                    before = len(out)
                    scan_text(cmd, "shell", src, findings=out)
                    if project_scope and len(out) == before:
                        out.append(Finding("HOOK-PROJECT", "LOW",
                                           "Repository-supplied %s hook" % event, src, 0, cmd[:150],
                                           "Runs automatically once you trust the folder."))
