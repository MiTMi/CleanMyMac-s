"""Threat-intelligence enrichment (all free tiers):
  deps.dev   - full dependency graph, provenance, OpenSSF Scorecard (no key)
  VirusTotal - file hashes / domains / URLs (free key: 4 req/min, 500/day, personal use)
  abuse.ch   - URLhaus + ThreatFox (domains/URLs/IPs), MalwareBazaar (hashes) (free Auth-Key)
Only hashes, domains and URLs leave the machine - never file contents."""
import base64
import hashlib
import json
import os
import re
import time
import urllib.parse

from . import net
from .model import Finding, GUARD_HOME

CONFIG = os.path.join(GUARD_HOME, "config.json")
CACHE = os.path.join(GUARD_HOME, "cache", "intel.json")
TTL = 3 * 86400
_cache = None
_deadline = [None]
WAIT_OK = [False]          # CLI may wait for the VirusTotal rate limit; hooks may not

# Big shared platforms: a host-level hit there means "someone once hosted malware on
# GitHub", not that this component is bad - look these up by exact URL instead.
SHARED = re.compile(r"(^|\.)(github\.com|githubusercontent\.com|gitlab\.com|bitbucket\.org|google\.com|"
                    r"googleapis\.com|googleusercontent\.com|gstatic\.com|amazonaws\.com|cloudfront\.net|"
                    r"azureedge\.net|windows\.net|azurewebsites\.net|dropbox\.com|dropboxusercontent\.com|"
                    r"discordapp\.com|discord\.com|mediafire\.com|onedrive\.live\.com|sharepoint\.com|"
                    r"firebasestorage\.app|appspot\.com|vercel\.app|netlify\.app|herokuapp\.com|"
                    r"workers\.dev|pages\.dev|jsdelivr\.net|unpkg\.com|cdnjs\.cloudflare\.com|"
                    r"npmjs\.org|npmjs\.com|pypi\.org|pythonhosted\.org|huggingface\.co|"
                    r"blogspot\.com|wordpress\.com|medium\.com|notion\.site|telegram\.org|t\.me)$", re.I)
BENIGN = re.compile(r"(^|\.)(anthropic\.com|claude\.ai|claude\.com|modelcontextprotocol\.io|apple\.com|"
                    r"microsoft\.com|mozilla\.org|w3\.org|schema\.org|json-schema\.org|example\.(com|org|net)|"
                    r"localhost|nodejs\.org|python\.org|readthedocs\.io|stackoverflow\.com|opensource\.org|"
                    r"creativecommons\.org|wikipedia\.org|spdx\.org|semver\.org|ietf\.org|ecma-international\.org|"
                    r"typescriptlang\.org|reactjs\.org|react\.dev|npm\.im|shields\.io|badgen\.net|"
                    r"swift\.org|developer\.apple\.com|openai\.com|docs\.rs|crates\.io|golang\.org|go\.dev)$", re.I)
URL_RX = re.compile(r"\b(?:https?|wss?)://([A-Za-z0-9.-]+\.[A-Za-z]{2,}|\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?"
                    r"(/[^\s\"'`<>)\]}]*)?")


# ------------------------------------------------------------------ config/cache
def keys():
    cfg = {}
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except Exception:
        pass
    return {"vt": os.environ.get("VT_API_KEY") or cfg.get("virustotal_key"),
            "abusech": os.environ.get("ABUSECH_AUTH_KEY") or cfg.get("abusech_key")}


def set_key(name, value):
    cfg = {}
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except Exception:
        pass
    cfg[name] = value
    os.makedirs(GUARD_HOME, exist_ok=True)
    fd = os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)


def _load():
    global _cache
    if _cache is None:
        try:
            with open(CACHE) as f:
                _cache = json.load(f)
        except Exception:
            _cache = {}
    return _cache


def _save():
    if _cache is None:
        return
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    now = time.time()
    keep = {k: v for k, v in _cache.items() if k.startswith("_") or now - v[0] < TTL}
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(keep, f)
    os.replace(tmp, CACHE)


def _cached(key, fn):
    c = _load()
    hit = c.get(key)
    if hit and time.time() - hit[0] < TTL:
        return hit[1]
    if _deadline[0] and time.time() > _deadline[0]:
        return None
    try:
        val = fn()
    except net.NetError:
        return None
    if val is not None:
        c[key] = [time.time(), val]
    return val


def set_budget(seconds):
    _deadline[0] = time.time() + seconds if seconds else None


# ------------------------------------------------------------------ deps.dev
DD = "https://api.deps.dev/v3"


def _q(s):
    return urllib.parse.quote(s, safe="")


def depsdev_version(system, name, version):
    return _cached("dd:v:%s:%s:%s" % (system, name, version), lambda: net.get_json(
        "%s/systems/%s/packages/%s/versions/%s" % (DD, system, _q(name), _q(version))))


def depsdev_deps(system, name, version):
    def f():
        d = net.get_json("%s/systems/%s/packages/%s/versions/%s:dependencies" % (DD, system, _q(name), _q(version)))
        return [[n["versionKey"]["name"], n["versionKey"]["version"], n.get("relation", "")]
                for n in d.get("nodes") or [] if n.get("relation") != "SELF" and n.get("versionKey")]
    return _cached("dd:d:%s:%s:%s" % (system, name, version), f)


def depsdev_scorecard(project_id):
    def f():
        d = net.get_json("%s/projects/%s" % (DD, _q(project_id)))
        sc = d.get("scorecard") or {}
        return {"score": sc.get("overallScore"), "date": sc.get("date")}
    return _cached("dd:p:" + project_id, f)


# ------------------------------------------------------------------ VirusTotal
def _vt_slot():
    c = _load()
    calls = [t for t in c.get("_vt_calls", []) if time.time() - t < 86400]
    if len(calls) >= 480:
        return False
    minute = [t for t in calls if time.time() - t < 60]
    if len(minute) >= 4:
        wait = 61 - (time.time() - min(minute))
        if not WAIT_OK[0] or (_deadline[0] and time.time() + wait > _deadline[0]):
            return False
        time.sleep(max(0, wait))
    calls.append(time.time())
    c["_vt_calls"] = calls
    return True


def vt(kind, value):
    """kind: files|domains|urls|ip_addresses -> {'malicious','suspicious','harmless','undetected'} or
    {'not_found': True}; None when no key / quota / error."""
    key = keys()["vt"]
    if not key:
        return None
    ident = value
    if kind == "urls":
        ident = base64.urlsafe_b64encode(value.encode()).decode().rstrip("=")

    def f():
        if not _vt_slot():
            return None
        try:
            d = net.get_json("https://www.virustotal.com/api/v3/%s/%s" % (kind, _q(ident)),
                             headers={"x-apikey": key})
        except net.NetError as e:
            if "HTTP 404" in str(e):
                return {"not_found": True}
            raise
        return (d.get("data") or {}).get("attributes", {}).get("last_analysis_stats") or {}
    return _cached("vt:%s:%s" % (kind, value), f)


# ------------------------------------------------------------------ abuse.ch
def _abuse_post(url, form=None, js=None):
    key = keys()["abusech"]
    if not key:
        return None
    if js is not None:
        return net.get_json(url, js, headers={"Auth-Key": key})
    body = urllib.parse.urlencode(form).encode()
    raw = net.get(url, data=body, headers={"Auth-Key": key,
                                           "Content-Type": "application/x-www-form-urlencoded"})
    return json.loads(raw.decode("utf-8"))


def urlhaus_host(host):
    def f():
        d = _abuse_post("https://urlhaus-api.abuse.ch/v1/host/", {"host": host})
        if d is None:
            return None
        if d.get("query_status") != "ok":
            return {"listed": False}
        urls = d.get("urls") or []
        return {"listed": True, "total": len(urls) or d.get("url_count"),
                "online": sum(1 for u in urls if u.get("url_status") == "online"),
                "threats": sorted({u.get("threat") for u in urls if u.get("threat")})[:3]}
    return _cached("uh:h:" + host, f) if keys()["abusech"] else None


def urlhaus_url(url):
    def f():
        d = _abuse_post("https://urlhaus-api.abuse.ch/v1/url/", {"url": url})
        if d is None:
            return None
        if d.get("query_status") != "ok":
            return {"listed": False}
        return {"listed": True, "online": 1 if d.get("url_status") == "online" else 0,
                "threats": [d.get("threat")] if d.get("threat") else []}
    return _cached("uh:u:" + url, f) if keys()["abusech"] else None


def threatfox(term):
    def f():
        d = _abuse_post("https://threatfox-api.abuse.ch/api/v1/", js={
            "query": "search_ioc", "search_term": term, "exact_match": True})
        if d is None:
            return None
        data = d.get("data") if d.get("query_status") == "ok" else None
        if not isinstance(data, list) or not data:
            return {"listed": False}
        top = max(data, key=lambda x: x.get("confidence_level") or 0)
        return {"listed": True, "malware": top.get("malware_printable"),
                "type": top.get("threat_type"), "confidence": top.get("confidence_level")}
    return _cached("tf:" + term, f) if keys()["abusech"] else None


def bazaar(sha256):
    def f():
        d = _abuse_post("https://mb-api.abuse.ch/api/v1/", {"query": "get_info", "hash": sha256})
        if d is None:
            return None
        if d.get("query_status") != "ok":
            return {"listed": False}
        rec = d.get("data")
        rec = rec[0] if isinstance(rec, list) and rec else (rec if isinstance(rec, dict) else d)
        return {"listed": True, "signature": rec.get("signature"), "file_type": rec.get("file_type")}
    return _cached("mb:" + sha256, f) if keys()["abusech"] else None
