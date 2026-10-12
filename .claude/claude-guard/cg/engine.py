"""Scanning of installed components + persistent state (baseline, trust, drift)."""
import fnmatch
import hashlib
import json
import os
import time

from .checks import mcp_config_checks, settings_checks, hook_checks, resolve_package
from .precheck import name_checks
from . import enrich
from .discover import discover_all, load_json
from .model import Finding, Result, GUARD_HOME, SEV_NAMES
from .scan import scan_tree, fingerprint_tree

STATE = os.path.join(GUARD_HOME, "state.json")
ALLOW = os.path.join(GUARD_HOME, "allowlist.json")


def load_state():
    st = load_json(STATE)
    if not isinstance(st, dict):
        st = {}
    st.setdefault("components", {})
    st.setdefault("trusted", {})
    st.setdefault("tools", {})
    return st


def save_state(st):
    os.makedirs(GUARD_HOME, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, indent=1, sort_keys=True)
    os.replace(tmp, STATE)


def load_allow():
    a = load_json(ALLOW)
    return a if isinstance(a, dict) else {}


def scan_component(c):
    out = []
    fp = hashlib.sha256(json.dumps(c.config or {}, sort_keys=True, default=str).encode()).hexdigest()
    ctx = {"skill": "skill", "agent": "skill", "command": "skill", "output-style": "skill",
           "rule": "skill", "instructions": "skill", "extension": "extension",
           "plugin": "plugin"}.get(c.kind, "plugin")
    meta = {}
    if c.kind == "mcp":
        out += mcp_config_checks(c.config or {}, c.source)
        pkg = resolve_package(c.config or {})
        if pkg and pkg[0] in ("npm", "pypi"):
            out += name_checks(pkg[0], pkg[1], c.source)
    elif c.kind == "settings":
        out += settings_checks(c.config or {}, c.source,
                               project_scope=c.scope.startswith("project:") and c.name == "settings.json")
    elif c.kind == "extension":
        out += mcp_config_checks(c.config or {}, c.source)
        if c.extra.get("enabled") is False:
            meta["disabled"] = True
    if c.kind == "plugin" and c.root:
        hj = os.path.join(c.root, "hooks", "hooks.json")
        data = load_json(hj)
        if isinstance(data, dict):
            hook_checks(data.get("hooks", data), hj, out)
        if os.path.isdir(os.path.join(c.root, "bin")):
            out.append(Finding("PLUGIN-BIN", "LOW", "Plugin puts executables on Claude's PATH",
                               os.path.join(c.root, "bin"), 0, "bin/",
                               "Claude may run these as bare commands."))
        meta["enabled"] = c.extra.get("enabled")
    if c.root:
        _, tfp, stats = scan_tree(c.root, ctx, out)
        fp = hashlib.sha256((fp + tfp).encode()).hexdigest()
        meta.update(stats)
        out += enrich.enrich_tree(c.root, ctx)
    url = (c.config or {}).get("url") if c.kind in ("mcp", "extension") else None
    if url:
        out += enrich.enrich_url(url, c.source)
    if c.kind == "workflow" and c.root:
        out.append(Finding("WORKFLOW-JS", "INFO", "Dynamic workflow script (executes JS)", c.root, 0,
                           "", "Review before running."))
    return Result(c, _dedupe(out), fp, meta)


def _dedupe(fs):
    seen, res = {}, []
    for f in fs:
        k = (f.rule, f.file)
        if k in seen:
            if f.level > seen[k].level:
                seen[k].severity, seen[k].snippet, seen[k].line = f.severity, f.snippet, f.line
            continue
        seen[k] = f
        res.append(f)
    return res


def apply_suppressions(result, st=None, allow=None):
    st = st if st is not None else load_state()
    allow = allow if allow is not None else load_allow()
    tr = st["trusted"].get(result.component.id)
    trusted = tr and tr.get("fingerprint") == result.fingerprint
    rules = allow.get("suppress") or []
    for f in result.findings:
        if trusted:
            f.suppressed = True
            continue
        for r in rules:
            if not isinstance(r, dict):
                continue
            if r.get("rule") and not fnmatch.fnmatch(f.rule, r["rule"]):
                continue
            if r.get("path") and not fnmatch.fnmatch(f.file, os.path.expanduser(r["path"])):
                continue
            if r.get("component") and r["component"] != result.component.id:
                continue
            f.suppressed = True
            break
    result.meta["trusted"] = bool(trusted)
    return result


def run_scan(filter_fn=None, projects=True):
    st, allow = load_state(), load_allow()
    results = []
    for c in discover_all(projects):
        if filter_fn and not filter_fn(c):
            continue
        r = apply_suppressions(scan_component(c), st, allow)
        results.append(r)
    return results


def record(results, st):
    now = int(time.time())
    for r in results:
        prev = st["components"].get(r.component.id) or {}
        keep = {"probe_worst": prev["probe_worst"]} if prev.get("probe_worst") and \
            prev.get("fingerprint") == r.fingerprint else {}
        st["components"][r.component.id] = dict(keep, **{
            "fingerprint": r.fingerprint, "worst": SEV_NAMES.get(r.worst, "NONE"),
            "counts": r.counts(), "last_scan": now, "source": r.component.source,
            "kind": r.component.kind, "name": r.component.name, "scope": r.component.scope,
        })


def fingerprint(c):
    fp = hashlib.sha256(json.dumps(c.config or {}, sort_keys=True, default=str).encode()).hexdigest()
    if c.root:
        fp = hashlib.sha256((fp + fingerprint_tree(c.root)).encode()).hexdigest()
    return fp


def drift(projects=True, full=False):
    """Detect new/changed/removed components and scan only those.
    Returns (changed_results, removed_ids, total_components)."""
    st, allow = load_state(), load_allow()
    comps = discover_all(projects)
    known = st["components"]
    changed = []
    for c in comps:
        prev = known.get(c.id)
        if not full and prev is not None and prev.get("fingerprint") == fingerprint(c):
            continue
        r = apply_suppressions(scan_component(c), st, allow)
        r.meta["change"] = "new" if prev is None else ("changed" if not full else "rescan")
        changed.append(r)
    ids = {c.id for c in comps}
    removed = [k for k in known if k not in ids]
    for k in removed:
        known.pop(k, None)
    record(changed, st)
    st["last_drift"] = int(time.time())
    save_state(st)
    return changed, removed, len(comps)


def quarantined(st=None):
    """Components whose last scan was CRITICAL and that the user hasn't trusted."""
    st = st or load_state()
    out = []
    for cid, info in st["components"].items():
        if "CRITICAL" in (info.get("worst"), info.get("probe_worst")):
            tr = st["trusted"].get(cid)
            if not tr or tr.get("fingerprint") != info.get("fingerprint"):
                out.append((cid, info))
    return out


def trust(cid, note=""):
    st = load_state()
    info = st["components"].get(cid)
    if not info:
        matches = [k for k in st["components"] if k == cid or k.startswith(cid + "@")
                   or k.split(":", 1)[-1].split("@")[0] == cid]
        if len(matches) != 1:
            return None, matches
        cid, info = matches[0], st["components"][matches[0]]
    st["trusted"][cid] = {"fingerprint": info["fingerprint"], "at": int(time.time()), "note": note}
    save_state(st)
    return cid, None


def untrust(cid):
    st = load_state()
    ok = st["trusted"].pop(cid, None) is not None
    save_state(st)
    return ok
