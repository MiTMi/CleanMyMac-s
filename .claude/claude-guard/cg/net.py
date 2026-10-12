"""Network + archive helpers (download only, never execute)."""
import io
import json
import os
import shutil
import ssl
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile

from .model import GUARD_HOME

UA = "claude-guard/1.0 (+local security scanner)"
MAX_DOWNLOAD = 60 * 1024 * 1024
MAX_EXTRACT = 300 * 1024 * 1024
TIMEOUT = float(os.environ.get("CLAUDE_GUARD_TIMEOUT", "20"))


class NetError(Exception):
    pass


def _ctx():
    ctx = ssl.create_default_context()
    for ca in (os.environ.get("SSL_CERT_FILE"), "/etc/ssl/cert.pem"):
        if ca and os.path.isfile(ca):
            try:
                ctx.load_verify_locations(ca)
            except Exception:
                pass
    try:
        import certifi  # optional
        ctx.load_verify_locations(certifi.where())
    except Exception:
        pass
    return ctx


def get(url, accept="application/json", limit=MAX_DOWNLOAD, data=None, headers=None):
    hdrs = {"User-Agent": UA, "Accept": accept}
    tok = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if tok and "api.github.com" in url:
        hdrs["Authorization"] = "Bearer " + tok
    hdrs.update(headers or {})
    req = urllib.request.Request(url, data=data, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=_ctx()) as r:
            buf = r.read(limit + 1)
    except urllib.error.HTTPError as e:
        raise NetError("HTTP %s for %s" % (e.code, url))
    except Exception as e:
        raise NetError("%s: %s" % (url, e))
    if len(buf) > limit:
        raise NetError("download larger than %d MB: %s" % (limit // 1048576, url))
    return buf


def get_json(url, data=None, headers=None):
    body = json.dumps(data).encode() if data is not None else None
    h = {"Content-Type": "application/json"} if body else {}
    h.update(headers or {})
    raw = get(url, data=body, headers=h)
    return json.loads(raw.decode("utf-8"))


def workdir():
    base = os.path.join(GUARD_HOME, "tmp")
    os.makedirs(base, exist_ok=True)
    return tempfile.mkdtemp(prefix="chk-", dir=base)


def cleanup(path):
    if path and path.startswith(os.path.join(GUARD_HOME, "tmp")):
        shutil.rmtree(path, ignore_errors=True)


def _safe_target(dest, name):
    name = name.replace("\\", "/")
    if name.startswith("/") or ".." in name.split("/"):
        return None
    t = os.path.realpath(os.path.join(dest, name))
    if not t.startswith(os.path.realpath(dest) + os.sep):
        return None
    return t


def extract(data, dest, hint=""):
    """Safely extract tar(.gz)/zip bytes. Returns list of warnings."""
    warns, total = [], 0
    bio = io.BytesIO(data)
    if zipfile.is_zipfile(bio):
        with zipfile.ZipFile(bio) as z:
            for info in z.infolist():
                if info.is_dir():
                    continue
                t = _safe_target(dest, info.filename)
                if t is None:
                    warns.append("path traversal entry: " + info.filename)
                    continue
                mode = (info.external_attr >> 16) & 0o170000
                if mode == 0o120000:
                    warns.append("symlink entry skipped: " + info.filename)
                    continue
                total += info.file_size
                if total > MAX_EXTRACT:
                    warns.append("archive too large, truncated")
                    break
                os.makedirs(os.path.dirname(t), exist_ok=True)
                with z.open(info) as src, open(t, "wb") as dst:
                    shutil.copyfileobj(src, dst)
        return warns
    bio.seek(0)
    try:
        tf = tarfile.open(fileobj=bio, mode="r:*")
    except tarfile.TarError:
        raise NetError("not a zip/tar archive" + (" (%s)" % hint if hint else ""))
    with tf:
        for m in tf.getmembers():
            if m.issym() or m.islnk():
                warns.append("link entry skipped: %s -> %s" % (m.name, m.linkname))
                continue
            if not m.isfile():
                continue
            t = _safe_target(dest, m.name)
            if t is None:
                warns.append("path traversal entry: " + m.name)
                continue
            total += m.size
            if total > MAX_EXTRACT:
                warns.append("archive too large, truncated")
                break
            os.makedirs(os.path.dirname(t), exist_ok=True)
            src = tf.extractfile(m)
            if src is None:
                continue
            with open(t, "wb") as dst:
                shutil.copyfileobj(src, dst)
    return warns


def single_subdir(path):
    """Tarballs usually wrap everything in package/ or repo-sha/."""
    try:
        entries = [e for e in os.listdir(path) if not e.startswith(".")]
    except OSError:
        return path
    if len(entries) == 1 and os.path.isdir(os.path.join(path, entries[0])):
        return os.path.join(path, entries[0])
    return path
