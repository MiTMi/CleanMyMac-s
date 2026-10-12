"""Pre-install vetting: npm / PyPI / GitHub / URL / local path / MCP config."""
import datetime as dt
import json
import os
import re
import urllib.parse

from . import net
from . import enrich
from . import rules as R
from .checks import mcp_config_checks, resolve_package, settings_checks, hook_checks
from .model import Component, Finding, Result, GUARD_HOME
from .scan import scan_tree

NEW_VERSION_DAYS = 7
NEW_PACKAGE_DAYS = 30


def _now():
    return dt.datetime.now(dt.timezone.utc)


def _age_days(iso):
    try:
        t = dt.datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return (_now() - t).total_seconds() / 86400.0
    except Exception:
        return None


def _lev(a, b):
    if abs(len(a) - len(b)) > 2:
        return 9
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def blocklist(eco):
    bad = dict(R.KNOWN_BAD.get(eco, {}))
    try:
        with open(os.path.join(GUARD_HOME, "blocklist.json")) as f:
            for n in json.load(f).get(eco, []):
                bad[n] = "In your personal blocklist"
    except Exception:
        pass
    return bad


def name_checks(eco, name, src):
    out = []
    bad = blocklist(eco)
    if name in bad:
        out.append(Finding("KNOWN-MALICIOUS", "CRITICAL", "Known malicious package: " + name,
                           src, 0, bad[name], "Do not install."))
    n = name.lower()
    for pop in R.POPULAR_PACKAGES:
        p = pop.lower()
        if n == p:
            return out
    for pop in R.POPULAR_PACKAGES:
        p = pop.lower()
        bare_n, bare_p = n.split("/")[-1], p.split("/")[-1]
        if (len(p) > 5 and _lev(n, p) <= 2) or \
                (p.startswith("@") and n == bare_p) or \
                (p.startswith("@") and n.startswith("@") and bare_n == bare_p and n != p):
            out.append(Finding("TYPOSQUAT", "HIGH", "Name is suspiciously close to '%s'" % pop,
                               src, 0, name, "Typosquats imitate popular MCP packages. "
                                             "Double-check the exact name/publisher."))
            break
    return out


def osv(eco, name, version):
    """Query OSV.dev (includes OpenSSF malicious-packages DB)."""
    q = {"package": {"name": name, "ecosystem": "npm" if eco == "npm" else "PyPI"}}
    if version:
        q["version"] = version
    try:
        res = net.get_json("https://api.osv.dev/v1/query", q)
    except net.NetError as e:
        return None, str(e)
    return res.get("vulns") or [], None


def osv_findings(eco, name, version, src):
    out = []
    vulns, err = osv(eco, name, version)
    if err:
        out.append(Finding("OSV-UNAVAILABLE", "INFO", "Could not query OSV.dev", src, 0, err[:150], ""))
        return out
    mal = [v for v in vulns if v.get("id", "").startswith("MAL-")]
    if mal:
        out.append(Finding("OSV-MALICIOUS", "CRITICAL", "OpenSSF/OSV lists this as MALICIOUS",
                           src, 0, ", ".join(v["id"] for v in mal[:5]),
                           "Reported malicious package/version. Do not install."))
    other = [v for v in vulns if not v.get("id", "").startswith("MAL-")]
    if other:
        out.append(Finding("OSV-VULN", "MEDIUM", "%d known vulnerabilities in this version" % len(other),
                           src, 0, ", ".join(v.get("id", "") for v in other[:6]),
                           "Prefer a patched version."))
    return out


def dep_malware(eco, deps, src):
    """Batch-check direct dependency names for malicious-package advisories."""
    out = []
    names = sorted(deps)[:150]
    if not names:
        return out
    qs = [{"package": {"name": n, "ecosystem": "npm" if eco == "npm" else "PyPI"}} for n in names]
    try:
        res = net.get_json("https://api.osv.dev/v1/querybatch", {"queries": qs})
    except net.NetError:
        return out
    for n, r in zip(names, res.get("results") or []):
        if any(v.get("id", "").startswith("MAL-") for v in r.get("vulns") or []):
            out.append(Finding("DEP-MALICIOUS-HISTORY", "MEDIUM",
                               "Dependency '%s' has had malicious releases" % n, src, 0, n,
                               "Make sure the resolved version is not one of the bad ones."))
    for n in names:
        if n in blocklist(eco):
            out.append(Finding("DEP-KNOWN-MALICIOUS", "CRITICAL", "Depends on known-malicious '%s'" % n,
                               src, 0, n, "Do not install."))
    return out


# ----------------------------------------------------------------------- npm
def check_npm(name, version=None):
    src = "npm:%s%s" % (name, "@" + version if version else "")
    comp = Component("package", name, src, None, None, "npm")
    out = name_checks("npm", name, src)
    meta = {}
    try:
        doc = net.get_json("https://registry.npmjs.org/" + urllib.parse.quote(name, safe="@"))
    except net.NetError as e:
        out.append(Finding("NPM-NOT-FOUND", "HIGH" if "404" in str(e) else "INFO",
                           "Package metadata unavailable", src, 0, str(e)[:150],
                           "A 404 can mean it was removed for malware, or a typo."))
        return Result(comp, out, meta=meta)
    tags = doc.get("dist-tags") or {}
    ver = version if version and version in (doc.get("versions") or {}) else tags.get("latest")
    if version and version not in (doc.get("versions") or {}) and version in tags:
        ver = tags[version]
    vd = (doc.get("versions") or {}).get(ver) or {}
    times = doc.get("time") or {}
    meta.update({"version": ver, "published": times.get(ver), "created": times.get("created"),
                 "maintainers": [m.get("name") for m in vd.get("maintainers") or []],
                 "repository": (vd.get("repository") or {}).get("url") if isinstance(
                     vd.get("repository"), dict) else vd.get("repository"),
                 "license": vd.get("license")})
    age_v, age_p = _age_days(times.get(ver) or ""), _age_days(times.get("created") or "")
    if age_v is not None and age_v < NEW_VERSION_DAYS:
        out.append(Finding("FRESH-RELEASE", "LOW", "Version %s published %.1f days ago" % (ver, age_v),
                           src, 0, "", "Hijacked releases are usually caught within days - "
                                       "consider pinning the previous version."))
    out += release_diff(doc, ver, src)
    if age_p is not None and age_p < NEW_PACKAGE_DAYS:
        out.append(Finding("NEW-PACKAGE", "MEDIUM", "Package is only %.0f days old" % age_p, src, 0, "",
                           "New packages have no track record."))
    if not meta["repository"]:
        out.append(Finding("NO-REPO", "LOW", "No source repository linked", src, 0, "",
                           "Published code can't be compared to a public repo."))
    if vd.get("deprecated"):
        out.append(Finding("DEPRECATED", "LOW", "Version is deprecated", src, 0,
                           str(vd["deprecated"])[:150], ""))
    try:
        dl = net.get_json("https://api.npmjs.org/downloads/point/last-week/" + name)
        meta["weekly_downloads"] = dl.get("downloads")
        if (dl.get("downloads") or 0) < 100:
            out.append(Finding("LOW-ADOPTION", "LOW", "Only %s downloads last week" % dl.get("downloads"),
                               src, 0, "", "Few eyes on it."))
    except net.NetError:
        pass
    out += osv_findings("npm", name, ver, src)
    dfind, dmeta, graph_ok = enrich.deps_findings("npm", name, ver, src)
    out += dfind
    meta.update(dmeta)
    if not graph_ok:
        out += dep_malware("npm", list((vd.get("dependencies") or {}).keys()), src)
    tarball = (vd.get("dist") or {}).get("tarball")
    fp = ""
    if tarball:
        wd = net.workdir()
        try:
            net.extract(net.get(tarball, accept="*/*"), wd, tarball)
            root = net.single_subdir(wd)
            _, fp, stats = scan_tree(root, "package", out)
            out += enrich.enrich_tree(root, "package")
            relativize(out, root, "%s@%s" % (name, ver))
            meta["files"] = stats["files"]
        except net.NetError as e:
            out.append(Finding("DOWNLOAD-FAILED", "INFO", "Could not download tarball", src, 0, str(e)[:150], ""))
        finally:
            net.cleanup(wd)
    return Result(comp, out, fp, meta)


def release_diff(doc, ver, src):
    """Compare this release with the previous one: classic account-takeover signs."""
    out = []
    times = doc.get("time") or {}
    vers = [v for v in (doc.get("versions") or {}) if v in times]
    vers.sort(key=lambda v: times[v])
    if ver not in vers or vers.index(ver) == 0:
        return out
    prev = vers[vers.index(ver) - 1]
    cur_d, prev_d = doc["versions"][ver], doc["versions"][prev]
    hooks = ("preinstall", "install", "postinstall")
    cur_s = {k: v for k, v in (cur_d.get("scripts") or {}).items() if k in hooks}
    prev_s = {k: v for k, v in (prev_d.get("scripts") or {}).items() if k in hooks}
    new = {k: v for k, v in cur_s.items() if prev_s.get(k) != v}
    if new:
        out.append(Finding("NEW-INSTALL-SCRIPT", "HIGH",
                           "Install script added/changed since %s" % prev, src, 0,
                           "; ".join("%s: %s" % kv for kv in new.items())[:150],
                           "The #1 pattern of hijacked npm releases (Shai-Hulud, nx, ...)."))
    cur_u = (cur_d.get("_npmUser") or {}).get("name")
    earlier = {(doc["versions"][v].get("_npmUser") or {}).get("name") for v in vers[:vers.index(ver)]}
    if cur_u and earlier and cur_u not in earlier:
        out.append(Finding("NEW-PUBLISHER", "MEDIUM",
                           "First release ever published by account '%s'" % cur_u, src, 0, "",
                           "Could be a new maintainer - or a stolen/new account."))
    tp = (prev_d.get("dist") or {}).get("attestations"), (cur_d.get("dist") or {}).get("attestations")
    if tp[0] and not tp[1]:
        out.append(Finding("PROVENANCE-DROPPED", "HIGH",
                           "Previous release had build provenance, this one doesn't", src, 0, "",
                           "Releases published from a stolen token usually lack provenance."))
    return out


def relativize(findings, root, label):
    root = os.path.realpath(root)
    for f in findings:
        if f.file and os.path.realpath(f.file).startswith(root + os.sep):
            f.file = label + "/" + os.path.relpath(os.path.realpath(f.file), root)


# ---------------------------------------------------------------------- PyPI
def check_pypi(name, version=None):
    src = "pypi:%s%s" % (name, "==" + version if version else "")
    comp = Component("package", name, src, None, None, "pypi")
    out = name_checks("pypi", name, src)
    meta = {}
    url = "https://pypi.org/pypi/%s/%sjson" % (name, (version + "/") if version else "")
    try:
        doc = net.get_json(url)
    except net.NetError as e:
        out.append(Finding("PYPI-NOT-FOUND", "HIGH" if "404" in str(e) else "INFO",
                           "Package metadata unavailable", src, 0, str(e)[:150], ""))
        return Result(comp, out, meta=meta)
    info = doc.get("info") or {}
    ver = info.get("version")
    files = doc.get("urls") or []
    first = None
    try:
        allrel = net.get_json("https://pypi.org/pypi/%s/json" % name).get("releases") or {}
        ups = [f.get("upload_time_iso_8601") for fl in allrel.values() for f in fl if f.get("upload_time_iso_8601")]
        first = min(ups) if ups else None
    except net.NetError:
        pass
    pub = min([f.get("upload_time_iso_8601") for f in files if f.get("upload_time_iso_8601")] or [""])
    meta.update({"version": ver, "published": pub, "created": first,
                 "repository": (info.get("project_urls") or {}).get("Source") or info.get("home_page")})
    age_v, age_p = _age_days(pub or ""), _age_days(first or "")
    if age_v is not None and age_v < NEW_VERSION_DAYS:
        out.append(Finding("FRESH-RELEASE", "LOW", "Version %s published %.1f days ago" % (ver, age_v),
                           src, 0, "", "Consider pinning an older, proven version."))
    if age_p is not None and age_p < NEW_PACKAGE_DAYS:
        out.append(Finding("NEW-PACKAGE", "MEDIUM", "Package is only %.0f days old" % age_p, src, 0, "", ""))
    if not meta["repository"]:
        out.append(Finding("NO-REPO", "LOW", "No source repository linked", src, 0, "", ""))
    out += osv_findings("pypi", name, ver, src)
    deps = set()
    for r in info.get("requires_dist") or []:
        m = re.match(r"^([A-Za-z0-9._-]+)", r)
        if m and "extra ==" not in r:
            deps.add(m.group(1))
    dfind, dmeta, graph_ok = enrich.deps_findings("pypi", name, ver, src)
    out += dfind
    meta.update(dmeta)
    if not graph_ok:
        out += dep_malware("pypi", deps, src)
    fp = ""
    picks = [f for f in files if f.get("packagetype") == "sdist"][:1] + \
            [f for f in files if f.get("packagetype") == "bdist_wheel"][:1]
    for f in picks:
        wd = net.workdir()
        try:
            net.extract(net.get(f["url"], accept="*/*"), wd, f["filename"])
            root = net.single_subdir(wd)
            _, fp, _ = scan_tree(root, "package", out)
            if f.get("packagetype") == "bdist_wheel" or len(picks) == 1:
                out += enrich.enrich_tree(root, "package")
            relativize(out, root, f["filename"])
        except net.NetError as e:
            out.append(Finding("DOWNLOAD-FAILED", "INFO", "Could not download " + f.get("filename", ""),
                               src, 0, str(e)[:150], ""))
        finally:
            net.cleanup(wd)
    return Result(comp, _dedupe(out), fp, meta)


def _dedupe(fs):
    seen, out = set(), []
    for f in fs:
        k = (f.rule, os.path.basename(f.file), f.snippet)
        if k not in seen:
            seen.add(k)
            out.append(f)
    return out
