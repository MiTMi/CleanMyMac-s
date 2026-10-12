"""Turn threat-intel lookups into findings."""
import hashlib
import os

from . import intel, net
from .model import Finding
from .scan import iter_files, file_kind, BIN_MAGIC, MAX_TEXT

MAX_VT = [12]             # VirusTotal lookups per run (free tier: 4/min, 500/day)
_vt_used = [0]
MAX_HOSTS = 25
MAX_SHARED_URLS = 8


def sources():
    k = intel.keys()
    return {"osv+deps.dev": True, "virustotal": bool(k["vt"]), "abuse.ch": bool(k["abusech"])}


def _vt(kind, value):
    if _vt_used[0] >= MAX_VT[0]:
        return None
    if not intel.keys()["vt"]:
        return None
    _vt_used[0] += 1
    return intel.vt(kind, value)


# ------------------------------------------------------------------ collection
def collect(root, context):
    """Hosts / shared-platform URLs / native binaries referenced by a component."""
    hosts, shared, bins = {}, {}, []
    if not root or not os.path.exists(root):
        return hosts, shared, bins
    for path, rel, vendor in iter_files(root):
        if os.path.islink(path):
            continue
        try:
            if os.path.getsize(path) > MAX_TEXT:
                continue
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            continue
        if data[:4].startswith(BIN_MAGIC) or data[:2] == b"MZ":
            if len(bins) < 5 and (not vendor or path.endswith(".node")):
                bins.append((path, hashlib.sha256(data).hexdigest()))
            continue
        if vendor:
            continue
        kind = file_kind(path, context, data[:4096], rel)
        if kind in (None, "doc"):
            continue
        text = data.decode("utf-8", "replace")
        for m in intel.URL_RX.finditer(text):
            host = m.group(1).lower().rstrip(".")
            if intel.BENIGN.search(host):
                continue
            if intel.SHARED.search(host):
                if m.group(2) and len(m.group(2)) > 1 and len(shared) < 50:
                    shared.setdefault(m.group(0)[:300], (path, kind))
                continue
            hosts.setdefault(host, (path, kind, m.group(0)[:200]))
    return hosts, shared, bins


# ------------------------------------------------------------------ verdicts
def _vt_finding(stats, what, src, snippet):
    if not stats or stats.get("not_found"):
        return None
    mal, sus = stats.get("malicious", 0), stats.get("suspicious", 0)
    if mal >= 3:
        return Finding("INTEL-VT", "CRITICAL", "VirusTotal: %d engines flag %s as malicious" % (mal, what),
                       src, 0, snippet, "Multiple independent AV engines agree. Treat as malware.")
    if mal >= 1 or sus >= 3:
        return Finding("INTEL-VT", "MEDIUM", "VirusTotal: %d malicious / %d suspicious for %s" % (mal, sus, what),
                       src, 0, snippet, "Low detection count - can be a false positive; review.")
    return None


def host_findings(hosts, shared, label):
    out = []
    ranked = sorted(hosts.items(), key=lambda kv: (kv[1][1] not in ("code", "shell", "config"),
                                                     not kv[0][0].isdigit()))
    for i, (host, (path, kind, url)) in enumerate(ranked[:MAX_HOSTS]):
        is_ip = host.replace(".", "").isdigit()
        tf = intel.threatfox(host)
        if tf and tf.get("listed"):
            out.append(Finding("INTEL-THREATFOX", "CRITICAL",
                               "ThreatFox: %s is a known IOC (%s, %s)" % (host, tf.get("malware"), tf.get("type")),
                               path, 0, url, "Listed by abuse.ch as attacker infrastructure."))
            continue
        uh = intel.urlhaus_host(host)
        if uh and uh.get("listed"):
            sev = "CRITICAL" if uh.get("online") else "HIGH"
            out.append(Finding("INTEL-URLHAUS", sev, "URLhaus: %s has distributed malware (%s URL(s), %d online)"
                               % (host, uh.get("total"), uh.get("online", 0)), path, 0,
                               url + "  " + ",".join(uh.get("threats") or []),
                               "Host is known for serving malware."))
            continue
        if i < 4:
            f = _vt_finding(_vt("ip_addresses" if is_ip else "domains", host), host, path, url)
            if f:
                out.append(f)
    for url, (path, kind) in list(shared.items())[:MAX_SHARED_URLS]:
        uh = intel.urlhaus_url(url)
        if uh and uh.get("listed"):
            out.append(Finding("INTEL-URLHAUS", "CRITICAL" if uh.get("online") else "HIGH",
                               "URLhaus: this exact URL distributed malware", path, 0, url[:150],
                               ",".join(uh.get("threats") or [])))
    return out


def hash_findings(bins, label=""):
    out = []
    for path, sha in bins:
        mb = intel.bazaar(sha)
        if mb and mb.get("listed"):
            out.append(Finding("INTEL-MALWAREBAZAAR", "CRITICAL",
                               "MalwareBazaar: known malware sample (%s)" % (mb.get("signature") or "unknown family"),
                               path, 0, "sha256 " + sha, "Exact file hash match."))
            continue
        f = _vt_finding(_vt("files", sha), os.path.basename(path), path, "sha256 " + sha)
        if f:
            out.append(f)
    return out


def enrich_tree(root, context, label=""):
    if not any(sources()[k] for k in ("virustotal", "abuse.ch")):
        return []
    hosts, shared, bins = collect(root, context)
    return host_findings(hosts, shared, label) + hash_findings(bins, label)


def enrich_url(url, src):
    m = intel.URL_RX.search(url or "")
    if not m:
        return []
    host = m.group(1).lower()
    if intel.SHARED.search(host):
        return host_findings({}, {url: (src, "config")}, src)
    return host_findings({host: (src, "config", url)}, {}, src)


def enrich_bytes(data, src):
    return hash_findings([(src, hashlib.sha256(data).hexdigest())])


# ------------------------------------------------------------------ dependencies
def osv_batch(eco, pkgs):
    """pkgs: [(name, version)] -> {(name, version): [ids]} (None on failure)."""
    res = {}
    for i in range(0, len(pkgs), 500):
        chunk = pkgs[i:i + 500]
        qs = [{"package": {"name": n, "ecosystem": "npm" if eco == "npm" else "PyPI"}, "version": v}
              for n, v in chunk]
        try:
            d = net.get_json("https://api.osv.dev/v1/querybatch", {"queries": qs})
        except net.NetError:
            return None
        for (n, v), r in zip(chunk, d.get("results") or []):
            ids = [x.get("id", "") for x in r.get("vulns") or []]
            if ids:
                res[(n, v)] = ids
    return res


def deps_findings(eco, name, version, src):
    """deps.dev graph + exact-version OSV check of every transitive dependency.
    Returns (findings, meta, graph_ok)."""
    system = "npm" if eco == "npm" else "pypi"
    out, meta = [], {}
    v = intel.depsdev_version(system, name, version) if version else None
    if v:
        prov = (v.get("slsaProvenances") or []) + (v.get("attestations") or [])
        meta["provenance"] = "verified" if any(p.get("verified") for p in prov) else \
            ("unverified" if prov else "none")
        mal = [a.get("id") for a in v.get("advisoryKeys") or [] if str(a.get("id", "")).startswith("MAL-")]
        if mal:
            out.append(Finding("DEPSDEV-MALICIOUS", "CRITICAL", "deps.dev lists a malicious-package advisory",
                               src, 0, ", ".join(mal[:5]), "Do not install."))
        repo = next((p["projectKey"]["id"] for p in v.get("relatedProjects") or []
                     if p.get("relationType") == "SOURCE_REPO" and p.get("projectKey")), None)
        if repo:
            sc = intel.depsdev_scorecard(repo)
            if sc and sc.get("score") is not None:
                meta["scorecard"] = "%.1f/10 (%s)" % (sc["score"], repo)
                if sc["score"] < 3:
                    out.append(Finding("LOW-SCORECARD", "LOW", "OpenSSF Scorecard %.1f/10 for %s" % (sc["score"], repo),
                                       src, 0, "", "Weak security practices in the source repo."))
    deps = intel.depsdev_deps(system, name, version) if version else None
    if not deps:
        return out, meta, deps is not None
    meta["dependencies"] = len(deps)
    hits = osv_batch(eco, sorted({(d[0], d[1]) for d in deps}))
    if hits is None:
        out.append(Finding("OSV-UNAVAILABLE", "INFO", "Could not check %d dependencies against OSV" % len(deps),
                           src, 0, "", ""))
        return out, meta, True
    mal = [(n, v) for (n, v), ids in hits.items() if any(i.startswith("MAL-") for i in ids)]
    for n, ver in mal[:5]:
        out.append(Finding("DEP-MALICIOUS", "CRITICAL", "Dependency %s@%s is a known MALICIOUS release" % (n, ver),
                           src, 0, ", ".join(i for i in hits[(n, ver)] if i.startswith("MAL-"))[:150],
                           "Pulled in automatically when you install this. Do not install."))
    vuln = [k for k in hits if k not in mal]
    if vuln:
        out.append(Finding("DEP-VULNS", "LOW", "%d of %d dependencies have known vulnerabilities" % (len(vuln), len(deps)),
                           src, 0, ", ".join("%s@%s" % k for k in vuln[:6])[:150], "Not malware; patch when convenient."))
    return out, meta, True
