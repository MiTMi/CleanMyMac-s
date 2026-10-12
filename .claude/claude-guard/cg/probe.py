"""Live MCP introspection: start a server, read tools/prompts, scan the
descriptions the model will see, and detect silent changes (rug pulls).

NOTE: probing a stdio server RUNS it. Only probe servers that are already
installed (Claude runs them anyway) or that already passed `check`."""
import hashlib
import json
import os
import queue
import subprocess
import threading
import time
import urllib.request

from . import net
from .model import Finding, Result, Component
from .scan import scan_text

PROTO = "2025-06-18"
TIMEOUT = float(os.environ.get("CLAUDE_GUARD_PROBE_TIMEOUT", "25"))


def _expand(s, cfg):
    if not isinstance(s, str):
        return s
    root = cfg.get("_plugin_root") or ""
    s = s.replace("${CLAUDE_PLUGIN_ROOT}", root).replace("${__dirname}", root)
    return os.path.expandvars(os.path.expanduser(s))


def _stdio(cfg):
    cmd = [_expand(cfg["command"], cfg)] + [_expand(a, cfg) for a in cfg.get("args") or []]
    env = dict(os.environ)
    for k, v in (cfg.get("env") or {}).items():
        env[k] = _expand(str(v), cfg)
    env.setdefault("PATH", "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
    if "/opt/homebrew/bin" not in env["PATH"]:
        env["PATH"] += ":/opt/homebrew/bin:/usr/local/bin"
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, env=env, cwd=cfg.get("cwd") or None,
                         start_new_session=True)
    q = queue.Queue()

    def reader():
        for line in iter(p.stdout.readline, b""):
            q.put(line)
        q.put(None)
    threading.Thread(target=reader, daemon=True).start()

    def send(obj):
        p.stdin.write((json.dumps(obj) + "\n").encode())
        p.stdin.flush()

    def call(mid, method, params=None):
        send({"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}})
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            try:
                line = q.get(timeout=max(0.1, deadline - time.time()))
            except queue.Empty:
                break
            if line is None:
                raise RuntimeError("server exited")
            try:
                msg = json.loads(line.decode("utf-8", "replace"))
            except ValueError:
                continue       # log noise on stdout
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(str(msg["error"])[:200])
                return msg.get("result") or {}
        raise RuntimeError("timeout waiting for %s" % method)

    def close():
        try:
            p.stdin.close()
        except Exception:
            pass
        try:
            os.killpg(p.pid, 15)
        except Exception:
            p.terminate()
        try:
            p.wait(3)
        except Exception:
            try:
                os.killpg(p.pid, 9)
            except Exception:
                p.kill()
    return call, send, close


def _http(cfg):
    url = cfg["url"]
    headers = {"Content-Type": "application/json",
               "Accept": "application/json, text/event-stream",
               "MCP-Protocol-Version": PROTO}
    headers.update({k: str(v) for k, v in (cfg.get("headers") or {}).items()})
    sess = {}

    def post(obj):
        h = dict(headers)
        if sess.get("id"):
            h["Mcp-Session-Id"] = sess["id"]
        req = urllib.request.Request(url, json.dumps(obj).encode(), h)
        try:
            r = urllib.request.urlopen(req, timeout=TIMEOUT, context=net._ctx())
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                raise RuntimeError("server requires authentication (HTTP %d) - probe not possible" % e.code)
            raise RuntimeError("HTTP %d" % e.code)
        sid = r.headers.get("Mcp-Session-Id")
        if sid:
            sess["id"] = sid
        body = r.read(5 * 1024 * 1024).decode("utf-8", "replace")
        if "text/event-stream" in (r.headers.get("Content-Type") or ""):
            msgs = []
            for line in body.splitlines():
                if line.startswith("data:"):
                    try:
                        msgs.append(json.loads(line[5:].strip()))
                    except ValueError:
                        pass
            return msgs
        return [json.loads(body)] if body.strip() else []

    def call(mid, method, params=None):
        for msg in post({"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}}):
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(str(msg["error"])[:200])
                return msg.get("result") or {}
        raise RuntimeError("no response for " + method)

    def send(obj):
        try:
            post(obj)
        except Exception:
            pass
    return call, send, lambda: None


def introspect(cfg):
    remote = bool(cfg.get("url")) and not cfg.get("command")
    call, send, close = (_http if remote else _stdio)(cfg)
    data = {"tools": [], "prompts": [], "server": {}, "instructions": ""}
    try:
        init = call(1, "initialize", {"protocolVersion": PROTO, "capabilities": {},
                                      "clientInfo": {"name": "claude-guard", "version": "1.0"}})
        data["server"] = init.get("serverInfo") or {}
        data["instructions"] = init.get("instructions") or ""
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        caps = init.get("capabilities") or {}
        cursor, mid = None, 10
        while True:
            res = call(mid, "tools/list", {"cursor": cursor} if cursor else {})
            data["tools"] += res.get("tools") or []
            cursor, mid = res.get("nextCursor"), mid + 1
            if not cursor or mid > 30:
                break
        if "prompts" in caps:
            try:
                data["prompts"] = call(50, "prompts/list").get("prompts") or []
            except Exception:
                pass
    finally:
        close()
    return data


def tool_hash(t):
    blob = json.dumps({"d": t.get("description"), "s": t.get("inputSchema"),
                       "a": t.get("annotations")}, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def probe_component(c, st):
    """Returns Result; updates st['tools'] snapshot (caller saves)."""
    cfg = dict(c.config or {})
    if c.extra.get("plugin_root"):
        cfg["_plugin_root"] = c.extra["plugin_root"]
    if c.kind == "extension" and c.root:
        cfg["_plugin_root"] = c.root
    src = "probe:" + c.id
    out = []
    try:
        data = introspect(cfg)
    except Exception as e:
        return Result(c, [Finding("PROBE-FAILED", "INFO", "Could not introspect server", src, 0,
                                  str(e)[:150], "")], meta={"probed": False})
    srv = data["server"]
    if data["instructions"]:
        scan_text(data["instructions"], "desc", src + "#instructions", findings=out)
    snap, prev = {}, (st.get("tools") or {}).get(c.id) or {}
    for t in data["tools"]:
        name = t.get("name", "?")
        desc = t.get("description") or ""
        text = "%s\n%s\n%s" % (name, desc, json.dumps(t.get("inputSchema") or {}))
        before = len(out)
        scan_text(text, "desc", "%s#tool:%s" % (src, name), findings=out)
        kinds = {f.rule for f in out[before:] if f.level >= 3}
        if len(kinds) >= 2 and kinds & {"PI-CONCEAL", "PI-SENSITIVE-ASK", "PI-TOOL-POISON", "CRED-SSH",
                                        "CRED-CLOUD", "PI-OVERRIDE", "PI-SHADOW"}:
            out.append(Finding("POISONED-TOOL", "CRITICAL", "Poisoned tool description: '%s'" % name,
                               "%s#tool:%s" % (src, name), 0, ", ".join(sorted(kinds)),
                               "Multiple independent injection signals in one tool. Remove this server."))
        if len(desc) > 2500:
            out.append(Finding("DESC-LONG", "LOW", "Very long tool description (%d chars)" % len(desc),
                               "%s#tool:%s" % (src, name), 0, desc[:120],
                               "Long descriptions are where poisoning hides."))
        snap[name] = tool_hash(t)
    for p in data["prompts"]:
        scan_text("%s\n%s" % (p.get("name"), p.get("description") or ""), "desc",
                  "%s#prompt:%s" % (src, p.get("name")), findings=out)
    if prev:
        changed = [n for n in snap if n in prev and prev[n] != snap[n]]
        added = [n for n in snap if n not in prev]
        if changed:
            out.append(Finding("RUG-PULL", "HIGH", "Tool definitions changed since last probe",
                               src, 0, ", ".join(changed)[:150],
                               "A server silently rewriting its tool descriptions is the "
                               "'rug pull' attack. Review before using it again."))
        if added:
            out.append(Finding("TOOLS-ADDED", "LOW", "New tools appeared", src, 0,
                               ", ".join(added)[:150], ""))
    st.setdefault("tools", {})[c.id] = snap
    return Result(c, out, meta={"probed": True, "server": "%s %s" % (srv.get("name", ""),
                                                                     srv.get("version", "")),
                                "tools": sorted(snap), "prompts": len(data["prompts"])})


def shadowing(all_tools):
    """all_tools: {server_id: [names]} -> findings for duplicated tool names."""
    seen, out = {}, []
    for sid, names in all_tools.items():
        for n in names:
            seen.setdefault(n, []).append(sid)
    for n, sids in seen.items():
        if len(sids) > 1:
            out.append(Finding("TOOL-NAME-COLLISION", "LOW", "Tool name '%s' offered by %d servers" % (n, len(sids)),
                               "probe", 0, ", ".join(sids)[:150],
                               "A malicious server can impersonate a trusted server's tool."))
    return out
