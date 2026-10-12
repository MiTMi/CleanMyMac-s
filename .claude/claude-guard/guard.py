#!/usr/bin/env python3
"""claude-guard - local security scanner for Claude Desktop & Claude Code
MCP servers, Desktop Extensions, skills, plugins, agents, commands and hooks.

  claude-guard scan [--all] [--min LEVEL] [--kind K] [--json] [--probe]
  claude-guard check <npm:pkg | pypi:pkg | github:o/r | URL | path | '{json}'>
  claude-guard probe [NAME ...] [--all]        # live tool-description audit
  claude-guard status                          # what changed / what is flagged
  claude-guard list                            # inventory
  claude-guard trust ID [--note TEXT] | untrust ID
  claude-guard quarantine ID                   # disable a flagged component
  claude-guard hook session-start|pre-tool-use # used by Claude Code hooks
  claude-guard watch-tick                      # used by the LaunchAgent
"""
import argparse
import json
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cg import engine, report  # noqa: E402
from cg.model import SEV_ORDER, short_path, GUARD_HOME  # noqa: E402

VERSION = "1.1.0"
EXIT = {4: 4, 3: 3, 2: 2}


def _exit_for(results):
    w = max([r.worst for r in results] or [-1])
    return EXIT.get(w, 0)


def cmd_scan(a):
    kinds = set(a.kind.split(",")) if a.kind else None
    flt = None
    if kinds or a.name:
        flt = lambda c: (not kinds or c.kind in kinds) and (not a.name or a.name.lower() in c.name.lower())
    t0 = time.time()
    results = engine.run_scan(flt, projects=not a.no_projects)
    if a.deep:
        results += _deep([r.component for r in results if r.component.kind == "mcp"])
    if a.probe:
        results += _probe([r.component for r in results if r.component.kind in ("mcp", "extension")])
    st = engine.load_state()
    engine.record([r for r in results if r.component.kind != "package"
                   and not r.component.name.endswith("[live tools]")], st)
    engine.save_state(st)
    if a.json:
        print(report.as_json(results))
    else:
        print(report.render(results, a.min, show_clean=a.all,
                            title="claude-guard %s - %s (%.1fs)" % (VERSION, report.summary_line(results),
                                                                   time.time() - t0)))
    return _exit_for(results)


def cmd_check(a):
    from cg.targets import check_target
    from cg import net
    try:
        results = check_target(a.target)
    except (ValueError, net.NetError) as e:
        print("claude-guard: %s" % e, file=sys.stderr)
        return 1
    for r in results:
        engine.apply_suppressions(r)
    if a.json:
        print(report.as_json(results))
    else:
        w = max([r.worst for r in results] or [-1])
        verdict = {4: "⛔ DO NOT INSTALL", 3: "⚠️  SUSPICIOUS - review the findings before installing",
                   2: "🔶 CAUTION - probably fine, read the notes", 1: "✅ OK (low-risk notes only)"}.get(w, "✅ CLEAN")
        print(report.render(results, a.min, show_clean=True, title="claude-guard check: %s" % a.target))
        print("\nVerdict: " + verdict)
        print("Static analysis can't prove safety: it catches known-bad patterns, not novel logic.")
    return _exit_for(results)


def _deep(comps):
    """Registry + OSV + tarball scan of every npm/PyPI package an MCP server runs."""
    from cg.checks import resolve_package
    from cg.precheck import check_npm, check_pypi
    out, seen = [], set()
    for c in comps:
        pkg = resolve_package(c.config or {})
        if not pkg or pkg[0] not in ("npm", "pypi") or pkg[:2] in seen:
            continue
        seen.add(pkg[:2])
        sys.stderr.write("checking %s:%s ...\n" % pkg[:2])
        r = (check_npm if pkg[0] == "npm" else check_pypi)(pkg[1], pkg[2])
        r.component.name = "%s (used by %s)" % (pkg[1], c.name)
        out.append(engine.apply_suppressions(r))
    return out


def _probe(comps):
    from cg.probe import probe_component, shadowing
    st = engine.load_state()
    res, tools = [], {}
    for c in comps:
        if c.kind == "extension" and not c.config:
            continue
        if c.kind == "mcp" and not (c.config or {}).get("command") and not (c.config or {}).get("url"):
            continue
        sys.stderr.write("probing %s ...\n" % c.id)
        r = probe_component(c, st)
        r.component = type(c)(c.kind, c.name + " [live tools]", c.source, None, c.config, c.scope)
        res.append(engine.apply_suppressions(r, st))
        if c.id in st["components"] and r.meta.get("probed"):
            from cg.model import SEV_NAMES
            st["components"][c.id]["probe_worst"] = SEV_NAMES.get(r.worst, "NONE")
        if r.meta.get("tools"):
            tools[c.id] = r.meta["tools"]
    engine.save_state(st)
    return res


def cmd_probe(a):
    from cg.discover import discover_all
    comps = [c for c in discover_all(True) if c.kind in ("mcp", "extension")]
    if a.names:
        comps = [c for c in comps if any(n == c.name or n == c.id or n.lower() in c.name.lower()
                                         for n in a.names)]
    elif not a.all:
        print("Specify server names or --all. Probing STARTS each server (as Claude would).")
        for c in comps:
            print("  %s" % c.id)
        return 0
    results = _probe(comps)
    print(report.as_json(results) if a.json else report.render(results, a.min, show_clean=True,
                                                                title="claude-guard probe"))
    return _exit_for(results)


def cmd_status(a):
    changed, removed, total = engine.drift(projects=not a.no_projects)
    st = engine.load_state()
    from cg.enrich import sources
    print("claude-guard %s - %d components tracked, state: %s" % (VERSION, total, short_path(engine.STATE)))
    print("intel: " + ", ".join("%s %s" % (n, "on" if on else "off") for n, on in sources().items()))
    if changed:
        print(report.render(changed, "LOW", show_clean=True, title="\nNew / changed since last check:"))
    if removed:
        print("\nRemoved: " + ", ".join(removed))
    flagged = [(cid, i) for cid, i in st["components"].items() if SEV_ORDER.get(i.get("worst"), -1) >= 3]
    if flagged:
        print("\nCurrently flagged (HIGH/CRITICAL):")
        for cid, i in sorted(flagged, key=lambda x: -SEV_ORDER.get(x[1].get("worst"), 0)):
            tr = st["trusted"].get(cid)
            trusted = tr and tr.get("fingerprint") == i.get("fingerprint")
            print("  %-8s %s%s   %s" % (i.get("worst"), cid, "  [trusted]" if trusted else "",
                                       short_path(i.get("source", ""))))
        print("\nDetails: claude-guard scan --name NAME     Accept: claude-guard trust ID")
    elif not changed:
        print("Nothing new. No HIGH/CRITICAL components.")
    lr = os.path.join(GUARD_HOME, "last-report.txt")
    if os.path.exists(lr):
        print("\nLast watcher report: %s" % short_path(lr))
    return 0


def cmd_list(a):
    from cg.discover import discover_all
    st = engine.load_state()
    for c in sorted(discover_all(not a.no_projects), key=lambda c: (c.kind, c.scope, c.name)):
        i = st["components"].get(c.id) or {}
        print("%-12s %-40s %-24s %s" % (c.kind, c.name[:40], c.scope[:24], i.get("worst", "unscanned")))
    return 0


def cmd_trust(a):
    cid, amb = engine.trust(a.id, a.note or "")
    if not cid:
        print("Unknown or ambiguous id. Candidates: %s" % (", ".join(amb) or "none - run `claude-guard scan` first"))
        return 1
    print("Trusted %s at its current content. Any change will be re-flagged." % cid)
    return 0


def cmd_untrust(a):
    print("Removed trust for %s" % a.id if engine.untrust(a.id) else "Not trusted: %s" % a.id)
    return 0


def cmd_quarantine(a):
    from cg.quarantine import quarantine
    ok, msg = quarantine(a.id)
    print(msg)
    return 0 if ok else 1


def cmd_hook(a):
    from cg import hooks, hookrun, net
    net.TIMEOUT = min(net.TIMEOUT, 10.0)   # keep Claude responsive if a registry hangs
    try:
        raw = sys.stdin.read()
        inp = json.loads(raw) if raw.strip() else {}
    except ValueError:
        inp = {}
    try:
        if a.event == "session-start":
            hooks.session_start(inp)
        elif a.event == "pre-tool-use":
            hookrun.pre_tool_use(inp)
    except Exception as e:   # never break the user's session because of the scanner
        sys.stderr.write("claude-guard hook error: %s\n" % e)
    return 0


def cmd_watch(a):
    from cg import hookrun
    try:
        hookrun.watch_tick()
    except Exception as e:
        sys.stderr.write("claude-guard watch error: %s\n" % e)
    return 0


def cmd_config(a):
    from cg import intel, enrich
    names = {"virustotal-key": "virustotal_key", "abusech-key": "abusech_key"}
    if a.action == "set":
        if a.name not in names or not a.value:
            print("usage: claude-guard config set virustotal-key|abusech-key VALUE")
            return 1
        intel.set_key(names[a.name], a.value.strip())
        print("Saved %s to %s (chmod 600)." % (a.name, short_path(intel.CONFIG)))
    k = intel.keys()
    mask = lambda v: (v[:4] + "..." + v[-3:]) if v else "not set"
    print("virustotal-key: %s\nabusech-key:    %s" % (mask(k["vt"]), mask(k["abusech"])))
    print("active sources: " + ", ".join(n for n, on in enrich.sources().items() if on))
    return 0


def cmd_intel(a):
    """Ad-hoc lookup of a domain, URL, IP, sha256 or local file."""
    import hashlib
    import re
    from cg import intel, enrich
    t = a.target.strip()
    out = {}
    if os.path.isfile(os.path.expanduser(t)):
        with open(os.path.expanduser(t), "rb") as f:
            t = hashlib.sha256(f.read()).hexdigest()
    if re.fullmatch(r"[0-9a-fA-F]{64}", t):
        out = {"malwarebazaar": intel.bazaar(t.lower()), "virustotal": intel.vt("files", t.lower())}
    elif t.startswith(("http://", "https://")):
        out = {"urlhaus": intel.urlhaus_url(t), "virustotal": intel.vt("urls", t)}
        host = re.sub(r"^https?://([^/:]+).*$", r"\1", t)
        out.update({"threatfox(host)": intel.threatfox(host), "urlhaus(host)": intel.urlhaus_host(host)})
    else:
        ip = re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", t)
        out = {"threatfox": intel.threatfox(t), "urlhaus": intel.urlhaus_host(t),
               "virustotal": intel.vt("ip_addresses" if ip else "domains", t)}
    for k, v in out.items():
        print("%-16s %s" % (k, "n/a (no key / quota / offline)" if v is None else json.dumps(v)))
    return 0


def cmd_install(a):
    import shutil
    from cg import setup
    src = os.path.dirname(os.path.abspath(__file__))
    app = os.path.join(GUARD_HOME, "app")
    py = os.path.abspath(sys.executable)
    if os.path.realpath(src) != os.path.realpath(app):
        shutil.rmtree(app, ignore_errors=True)
        os.makedirs(app)
        shutil.copy2(os.path.join(src, "guard.py"), app)
        shutil.copytree(os.path.join(src, "cg"), os.path.join(app, "cg"),
                        ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copytree(os.path.join(src, "skill"), os.path.join(app, "skill"))
    guard = os.path.join(app, "guard.py")
    bindir = os.path.join(GUARD_HOME, "bin")
    os.makedirs(bindir, exist_ok=True)
    wrapper = os.path.join(bindir, "claude-guard")
    with open(wrapper, "w") as f:
        f.write('#!/bin/sh\nexec "%s" "%s" "$@"\n' % (py, guard))
    os.chmod(wrapper, 0o755)
    from cg.discover import claude_dir
    sk = os.path.join(claude_dir(), "skills", "claude-guard")
    os.makedirs(sk, exist_ok=True)
    shutil.copy2(os.path.join(app, "skill", "SKILL.md"), os.path.join(sk, "SKILL.md"))
    print("✓ installed to %s (python: %s)" % (short_path(app), py))
    print("✓ command:  %s" % wrapper)
    print("✓ skill:    %s  (/claude-guard in Claude Code)" % short_path(sk))
    if not a.no_hooks:
        print("✓ hooks:    SessionStart + PreToolUse added to %s" % short_path(setup.install_hooks(py, guard)))
    if not a.no_agent:
        paths = setup.install_agent(py, guard)
        if paths is not None:
            print("✓ watcher:  LaunchAgent watching %d locations (Desktop config, Extensions, skills, plugins)"
                  % len(paths))
    print("\nBaseline scan of everything currently installed:\n")
    results = engine.run_scan(None, projects=True)
    st = engine.load_state()
    engine.record(results, st)
    engine.save_state(st)
    print(report.render(results, "MEDIUM", show_clean=False, title=report.summary_line(results)))
    return 0


def cmd_install_repo(a):
    from cg import setup
    src = os.path.dirname(os.path.abspath(__file__))
    paths = setup.install_repo(a.repo, src, a.everywhere)
    print("Added to %s:\n  %s" % (a.repo, "\n  ".join(paths)))
    print("Hooks run %s. Commit and push:" % ("in every session" if a.everywhere else
                                              "only in cloud sessions (CLAUDE_CODE_REMOTE=true)"))
    print('  git -C %s add .claude && git -C %s commit -m "Add claude-guard" && git -C %s push'
          % (a.repo, a.repo, a.repo))
    return 0


def cmd_uninstall_repo(a):
    from cg import setup
    setup.uninstall_repo(a.repo)
    print("Removed claude-guard from %s (commit the change)." % a.repo)
    return 0


def cmd_uninstall(a):
    import shutil
    from cg import setup
    from cg.discover import claude_dir
    setup.uninstall_hooks()
    setup.uninstall_agent()
    shutil.rmtree(os.path.join(claude_dir(), "skills", "claude-guard"), ignore_errors=True)
    for d in ("app", "bin", "tmp"):
        shutil.rmtree(os.path.join(GUARD_HOME, d), ignore_errors=True)
    if a.purge:
        shutil.rmtree(GUARD_HOME, ignore_errors=True)
    print("claude-guard removed%s." % (" (state purged)" if a.purge else "; state kept in " + short_path(GUARD_HOME)))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="claude-guard", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", action="version", version=VERSION)
    sub = p.add_subparsers(dest="cmd")

    def common(sp, json_=True):
        if json_:
            sp.add_argument("--json", action="store_true")
        sp.add_argument("--min", default="LOW", choices=list(SEV_ORDER), help="hide findings below")
        return sp

    s = common(sub.add_parser("scan", help="audit everything installed"))
    s.add_argument("--all", action="store_true", help="also list clean components")
    s.add_argument("--kind", help="comma list: mcp,extension,skill,plugin,agent,command,settings,...")
    s.add_argument("--name")
    s.add_argument("--deep", action="store_true", help="also vet every npm/PyPI package MCP servers run (network)")
    s.add_argument("--probe", action="store_true", help="also start MCP servers and audit live tools")
    s.add_argument("--no-projects", action="store_true", help="skip per-project .claude/.mcp.json")
    s.set_defaults(fn=cmd_scan)
    s = common(sub.add_parser("check", help="vet something BEFORE installing it"))
    s.add_argument("target")
    s.set_defaults(fn=cmd_check)
    s = common(sub.add_parser("probe", help="start MCP servers and audit their live tool descriptions"))
    s.add_argument("names", nargs="*")
    s.add_argument("--all", action="store_true")
    s.set_defaults(fn=cmd_probe)
    s = sub.add_parser("status", help="drift since last check + flagged components")
    s.add_argument("--no-projects", action="store_true")
    s.set_defaults(fn=cmd_status)
    s = sub.add_parser("list", help="inventory")
    s.add_argument("--no-projects", action="store_true")
    s.set_defaults(fn=cmd_list)
    s = sub.add_parser("trust", help="accept a component at its current content")
    s.add_argument("id")
    s.add_argument("--note")
    s.set_defaults(fn=cmd_trust)
    s = sub.add_parser("untrust")
    s.add_argument("id")
    s.set_defaults(fn=cmd_untrust)
    s = sub.add_parser("quarantine", help="disable a component (reversible)")
    s.add_argument("id")
    s.set_defaults(fn=cmd_quarantine)
    s = sub.add_parser("hook")
    s.add_argument("event", choices=["session-start", "pre-tool-use"])
    s.set_defaults(fn=cmd_hook)
    s = sub.add_parser("watch-tick")
    s.set_defaults(fn=cmd_watch)
    s = sub.add_parser("install", help="install hooks, skill and watcher for this user")
    s.add_argument("--no-hooks", action="store_true")
    s.add_argument("--no-agent", action="store_true")
    s.set_defaults(fn=cmd_install)
    s = sub.add_parser("uninstall")
    s.add_argument("--purge", action="store_true", help="also delete state/allowlist")
    s.set_defaults(fn=cmd_uninstall)
    s = sub.add_parser("install-repo", help="vendor into a repo for Claude Code cloud sessions")
    s.add_argument("repo")
    s.add_argument("--everywhere", action="store_true", help="also run the repo hooks locally")
    s.set_defaults(fn=cmd_install_repo)
    s = sub.add_parser("uninstall-repo")
    s.add_argument("repo")
    s.set_defaults(fn=cmd_uninstall_repo)
    s = sub.add_parser("config", help="API keys for VirusTotal / abuse.ch")
    s.add_argument("action", choices=["show", "set"])
    s.add_argument("name", nargs="?")
    s.add_argument("value", nargs="?")
    s.set_defaults(fn=cmd_config)
    s = sub.add_parser("intel", help="look up a domain, URL, IP, sha256 or file in threat intel")
    s.add_argument("target")
    s.set_defaults(fn=cmd_intel)
    a = p.parse_args(argv)
    if not getattr(a, "fn", None):
        p.print_help()
        return 0
    from cg import intel, enrich
    if a.cmd == "hook":
        intel.set_budget(25)
        enrich.MAX_VT[0] = 3
    elif a.cmd == "watch-tick":
        intel.set_budget(90)
        enrich.MAX_VT[0] = 4
    else:
        intel.WAIT_OK[0] = True
        enrich.MAX_VT[0] = 8 if a.cmd in ("scan", "status", "install") else 12
    try:
        return a.fn(a)
    finally:
        try:
            intel._save()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
