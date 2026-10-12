"""File-tree scanning engine."""
import hashlib
import json
import os
import re

from .model import Finding
from . import rules as R

MAX_TEXT = 1536 * 1024
MAX_FILES = 20000
VENDOR_DIRS = {"node_modules", "site-packages", "dist-packages", ".venv", "venv",
               "vendor", "bower_components", "__pypackages__", "Pods", ".bundle"}
SKIP_DIRS = {".git", ".hg", ".svn", "__pycache__", ".mcpb-cache", ".DS_Store"}
CODE_EXT = {".js", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".tsx", ".jsx", ".py",
            ".pyw", ".rb", ".go", ".rs", ".swift", ".php", ".pl", ".lua", ".java",
            ".kt", ".cs", ".m", ".mm", ".c", ".cc", ".cpp", ".vbs", ".ps1", ".applescript",
            ".scpt", ".jxa"}
SHELL_EXT = {".sh", ".bash", ".zsh", ".command", ".fish", ".ksh"}
INSTR_EXT = {".md", ".mdx", ".markdown", ".txt", ".rst"}
CONFIG_EXT = {".json", ".jsonc", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".plist",
              ".env"}
SKIP_EXT = {".map", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg", ".woff",
            ".woff2", ".ttf", ".otf", ".eot", ".mp3", ".mp4", ".mov", ".wav", ".pdf",
            ".lock", ".d.ts"}
DOC_NAMES = re.compile(r"^(readme|changelog|changes|history|license|licence|contributing|"
                       r"code_of_conduct|security|authors|notice)", re.I)
BIN_MAGIC = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe",
             b"\x7fELF", b"MZ")


def snippet_of(text, start, end, width=150):
    a = max(0, start - 30)
    s = text[a:min(len(text), max(end, start + 40) + 30)]
    s = R.TAG_CHARS.sub(lambda m: "[HIDDEN:%s]" % decode_tags(m.group(0)), s)
    s = R.ZERO_WIDTH.sub("[ZW]", s)
    s = R.BIDI.sub("[BIDI]", s)
    s = " ".join(s.split())
    return s[:width] + ("..." if len(s) > width else "")


def decode_tags(s):
    out = []
    for ch in s:
        cp = ord(ch) - 0xE0000
        if 0x20 <= cp < 0x7F:
            out.append(chr(cp))
    return "".join(out)[:200]


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


NON_SHIPPED = re.compile(r"(^|/)(\.github|\.gitlab|\.circleci|tests?|__tests__|spec|e2e|examples?|"
                         r"benchmarks?|docs?|fixtures|\.husky|\.devcontainer)/|(^|/)\.pre-commit|"
                         r"(^|/)_CodeSignature/|\.(abi\.json|swiftinterface|swiftdoc)$", re.I)


def file_kind(path, context, head, rel="", vendor=False):
    """Classify a file for rule selection. context: skill|plugin|package|repo|extension."""
    name = os.path.basename(path)
    low = name.lower()
    ext = os.path.splitext(low)[1]
    if low.endswith(".d.ts") or ext in SKIP_EXT:
        return None
    if vendor and os.path.splitext(low)[1] in INSTR_EXT:
        return "doc"     # dependency docs are never loaded as instructions
    if context != "skill" and rel and NON_SHIPPED.search(rel.replace(os.sep, "/")):
        return "doc"     # CI, tests, examples: not executed by installing/using it
    if ext in SHELL_EXT:
        return "shell"
    if ext in CODE_EXT:
        return "code"
    if ext in INSTR_EXT:
        rel = path.replace("\\", "/").lower()
        if context in ("package",) and (DOC_NAMES.match(low) or "/docs/" in rel
                                        or "/examples/" in rel):
            return "doc"
        if context == "package" and low != "skill.md":
            return "doc"
        return "instr"
    if ext in CONFIG_EXT:
        return "config"
    if head.startswith(b"#!"):
        first = head.split(b"\n", 1)[0]
        if b"python" in first or b"node" in first or b"ruby" in first or b"perl" in first:
            return "code"
        return "shell"
    if not ext and b"\x00" not in head[:2048]:
        r = "/" + (rel or "").replace(os.sep, "/")
        if context == "skill" or "/bin/" in r or "/scripts/" in r or "/hooks/" in r:
            return "shell"
    return None


def is_minified(text):
    lines = text.count("\n") + 1
    return len(text) > 4000 and len(text) / lines > 400


def scan_text(text, kind, path, vendor=False, findings=None, rel=""):
    """Apply all rules + special checks to a text blob."""
    out = findings if findings is not None else []
    low = text.lower()
    minified = kind == "code" and is_minified(text)
    seen = set()
    for rule in R.RULES:
        if kind not in rule.kinds:
            continue
        if vendor and not rule.vendor:
            continue
        if minified and rule.id.startswith("OBF-"):
            continue
        if rule.hints and not any(h in low for h in rule.hints):
            continue
        matches = list(rule.rx.finditer(text))
        if kind == "code" and not rule.id.startswith("IOC"):
            matches = [x for x in matches if not _in_comment(text, x.start())]
        if rule.id.startswith("PI-"):
            matches = [x for x in matches if not _quoted(text, x.start())]
        if not matches:
            continue
        m = matches[0]
        if rule.id == "OBF-BLOB" and _blob_is_benign(text, m):
            continue
        key = (rule.id, path)
        if key in seen:
            continue
        seen.add(key)
        sev = rule.severity
        if vendor and sev == "HIGH" and rule.id.startswith(("EXFIL-PASTE", "CRED-KEYCHAIN")):
            sev = "MEDIUM"   # common in big dependency trees; still worth a look
        if kind == "code" and sev == "HIGH" and rule.id.startswith(("PI-", "PIPE-TO-SHELL", "BYPASS",
                                                                     "ENV-INJECTION")):
            sev = "MEDIUM"   # usually a string in code; the live probe judges real descriptions
        if rule.id == "ENV-INJECTION" and kind == "code" and m.group(0).upper().startswith("LD_PRELOAD"):
            sev = "LOW"      # Linux-only mechanism, inert on macOS
        if kind == "instr" and rule.id in ("PIPE-TO-SHELL", "SUDO"):
            sev = "MEDIUM" if rule.id == "PIPE-TO-SHELL" else "LOW"   # install docs; Bash hook still asks at run time
        if kind == "code" and rule.id.startswith("CRED-") and rule.id != "CRED-BROWSER" and \
                not any(_home_ctx(text, x.start()) for x in matches):
            sev = "LOW"      # a bare file name (e.g. a deny-list), not a path into your home folder
        out.append(Finding(rule.id, sev, rule.title, path, line_of(text, m.start()),
                           snippet_of(text, m.start(), m.end()), rule.advice,
                           len(matches)))
    if kind == "doc":
        return out
    _unicode_checks(text, kind, path, out, vendor)
    if kind in ("instr", "desc") and not vendor:
        _html_comment_check(text, path, out)
    if kind in ("code", "shell") and not vendor:
        _combo_check(text, path, out)
    return out


def _quoted(text, pos):
    before = text[max(0, pos - 2):pos]
    return any(q in before for q in ('"', "\u201c", "'", "`", "\u00ab", "\u2018"))


def _home_ctx(text, pos):
    w = text[max(0, pos - 100):pos]
    return bool(re.search(r"home|expanduser|HOME|~|/Users/|getenv|environ|os\.path\.join\([^)]*$", w))


def _in_comment(text, pos):
    ls = text.rfind("\n", 0, pos) + 1
    head = text[ls:pos].lstrip()
    return head.startswith(("//", "#", "*", "/*", "<!--", "--", ";"))


def _blob_is_benign(text, m):
    ctx = text[max(0, m.start() - 80):m.start()].lower()
    return any(k in ctx for k in ("data:", "image/", "font/", "sourcemappingurl",
                                  "integrity", "sha512-", "sha384-", "-----begin",
                                  "png", "woff", "svg", "certificate"))


def _unicode_checks(text, kind, path, out, vendor=False):
    tags = R.TAG_CHARS.search(text)
    if tags:
        out.append(Finding("UNICODE-TAGS", "CRITICAL",
                           "Invisible Unicode tag characters (ASCII smuggling)",
                           path, line_of(text, tags.start()),
                           "hidden text: " + decode_tags(tags.group(0)),
                           "Invisible instructions only the model can read."))
    if vendor:
        return
    bidi = R.BIDI.search(text)
    if bidi:
        out.append(Finding("UNICODE-BIDI", "HIGH", "Bidirectional override characters",
                           path, line_of(text, bidi.start()),
                           snippet_of(text, bidi.start(), bidi.end()),
                           "Trojan-Source: code/text displays differently than it executes."))
    zw = R.ZERO_WIDTH.findall(text)
    if len(zw) >= 3 and kind in ("instr", "desc", "code", "shell", "config"):
        m = R.ZERO_WIDTH.search(text)
        out.append(Finding("UNICODE-ZW", "LOW" if kind == "code" else "HIGH",
                           "Zero-width characters (%d)" % len(zw), path,
                           line_of(text, m.start()), snippet_of(text, m.start(), m.end()),
                           "Used to hide or split instructions/keywords from review.",
                           len(zw)))


def _html_comment_check(text, path, out):
    for m in R.HTML_COMMENT.finditer(text):
        body = m.group(1)
        if len(body.strip()) > 20 and R.IMPERATIVE.search(body):
            out.append(Finding("PI-HTML-COMMENT", "HIGH",
                               "Hidden instructions inside an HTML comment", path,
                               line_of(text, m.start()), snippet_of(text, m.start(), m.end()),
                               "Invisible in rendered Markdown but fully read by Claude."))
            return


def _combo_check(text, path, out):
    cred = next((m for m in R.CRED_RX.finditer(text) if not _in_comment(text, m.start())
                 and _home_ctx(text, m.start() + 1)), None)
    if cred and R.NET_RX.search(text):
        weak = re.search(r"netrc|npmrc|docker/config|kube/config", cred.group(0), re.I)
        out.append(Finding("COMBO-CRED-NET", "MEDIUM" if weak else "CRITICAL",
                           "Reads credentials AND has network egress in the same file",
                           path, line_of(text, cred.start()),
                           snippet_of(text, cred.start(), cred.end()),
                           "Credential access + outbound network = exfiltration capability."))


# ------------------------------------------------------------- skill specifics
FRONTMATTER = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.S)
BANG_INJECT = re.compile(r"!`([^`\n]+)`")
DANGEROUS_CMD = re.compile(r"curl|wget|\bnc\b|base64|ssh|scp|eval|osascript|security\s|"
                           r"python[0-9.]*\s+-c|node\s+-e|\|\s*(ba|z)?sh|rm\s+-rf|env\b|printenv", re.I)


def skill_checks(text, path, out):
    fm = FRONTMATTER.match(text)
    if fm:
        head = fm.group(1)
        at = re.search(r"^allowed-tools\s*:\s*(.+)$", head, re.M)
        if at:
            val = at.group(1)
            if re.search(r"Bash\s*(\(\s*\*?\s*\))?\s*(,|$|\])", val) or "Bash(*)" in val:
                out.append(Finding("SKILL-BASH-ALL", "MEDIUM",
                                   "Skill pre-approves unrestricted Bash", path,
                                   line_of(text, fm.start(1) + at.start()), val.strip()[:150],
                                   "Every shell command the skill triggers runs without asking."))
            elif re.search(r"Bash\(\s*\*\s*\)|Bash\([^)]*(curl|wget|\bnc\b|ssh|scp)", val):
                out.append(Finding("SKILL-BASH-NET", "MEDIUM",
                                   "Skill pre-approves network-capable shell commands", path,
                                   line_of(text, fm.start(1) + at.start()), val.strip()[:150],
                                   "Review exactly what is pre-approved."))
        if re.search(r"^hooks\s*:", head, re.M):
            out.append(Finding("SKILL-HOOKS", "MEDIUM",
                               "Skill registers hooks that stay active for the session",
                               path, 1, "hooks: in frontmatter",
                               "Hook commands run automatically on later tool calls."))
        if re.search(r"^shell\s*:", head, re.M):
            out.append(Finding("SKILL-SHELL", "LOW", "Skill sets a custom shell", path, 1,
                               "shell: in frontmatter", ""))
    for m in BANG_INJECT.finditer(text):
        cmd = m.group(1)
        dangerous = DANGEROUS_CMD.search(cmd)
        out.append(Finding("SKILL-BANG-EXEC", "HIGH" if dangerous else "LOW",
                           "Shell command auto-runs when the skill loads (!`...`)",
                           path, line_of(text, m.start()), cmd[:150],
                           "Runs on invocation before Claude or you can review it."))
        if dangerous:
            scan_text(cmd, "shell", path, findings=out)


# ---------------------------------------------------------- package specifics
INSTALL_HOOKS = ("preinstall", "install", "postinstall", "prepare", "preprepare",
                 "postprepare", "prepublish")


def package_json_checks(text, path, out):
    try:
        pj = json.loads(text)
    except Exception:
        return
    scripts = pj.get("scripts") or {}
    if not isinstance(scripts, dict):
        return
    for k in INSTALL_HOOKS:
        v = scripts.get(k)
        if not isinstance(v, str):
            continue
        if k == "prepare" and re.match(r"^\s*(husky|tsc|npm run build|node-gyp|"
                                       r"patch-package|ts-patch|npx only-allow)", v):
            continue
        bad = re.search(r"curl|wget|eval|base64|https?://|\|\s*sh|setup_bun|bun_environment|"
                        r"python\s+-c", v, re.I)
        sev = "HIGH" if bad else ("MEDIUM" if k in ("preinstall", "install", "postinstall") else "LOW")
        out.append(Finding("NPM-INSTALL-SCRIPT", sev,
                           "Runs a script automatically on npm install (%s)" % k,
                           path, 0, v[:150],
                           "Install scripts execute before you ever use the package."))


def pth_check(text, path, out):
    if re.search(r"^\s*import\s", text, re.M) or "exec(" in text:
        out.append(Finding("PY-PTH-EXEC", "HIGH",
                           ".pth file executes code at every Python start-up", path, 1,
                           snippet_of(text, 0, 80),
                           "A known PyPI malware persistence trick."))


def setup_py_check(text, path, out):
    if re.search(r"cmdclass|class\s+\w+\((install|develop|egg_info)\)", text) and \
            re.search(r"urlopen|requests|subprocess|os\.system|exec\(|socket", text):
        out.append(Finding("PY-SETUP-HOOK", "HIGH",
                           "setup.py overrides install commands and runs code/network",
                           path, 1, "", "Executes during pip install."))


# --------------------------------------------------------------- tree walking
def iter_files(root):
    """Yield (path, rel, vendor) for files under root (or root itself)."""
    if os.path.isfile(root):
        yield root, os.path.basename(root), False
        return
    count = 0
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        rel_dir = os.path.relpath(dirpath, root)
        parts = rel_dir.split(os.sep)
        vendor = bool(set(parts) & VENDOR_DIRS) or any(
            p.endswith((".framework", ".xcframework", ".bundle", ".app", ".dylib")) for p in parts)
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            count += 1
            if count > MAX_FILES:
                return
            p = os.path.join(dirpath, fn)
            yield p, os.path.normpath(os.path.join(rel_dir, fn)), vendor


def fingerprint_tree(root):
    """Same hash as scan_tree() produces, without running any rules."""
    h = hashlib.sha256()
    if not root or not os.path.exists(root):
        return ""
    for path, rel, vendor in sorted(iter_files(root), key=lambda t: t[1]):
        if os.path.islink(path):
            h.update(("L|%s|%s\n" % (rel, os.path.realpath(path))).encode("utf-8", "replace"))
            continue
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if size > MAX_TEXT:
            h.update(("S|%s|%d\n" % (rel, size)).encode("utf-8", "replace"))
            continue
        try:
            with open(path, "rb") as f:
                data = f.read()
        except (OSError, IOError):
            continue
        h.update(("F|%s|" % rel).encode("utf-8", "replace") + hashlib.sha256(data).digest())
    return h.hexdigest()


def scan_tree(root, context="plugin", out=None):
    """Scan a directory/file. Returns (findings, fingerprint, stats)."""
    out = out if out is not None else []
    h = hashlib.sha256()
    stats = {"files": 0, "scanned": 0, "skipped_large": 0, "binaries": 0, "vendor_files": 0}
    if not root or not os.path.exists(root):
        return out, "", stats
    root_real = os.path.realpath(root)
    for path, rel, vendor in sorted(iter_files(root), key=lambda t: t[1]):
        stats["files"] += 1
        if vendor:
            stats["vendor_files"] += 1
        if os.path.islink(path):
            target = os.path.realpath(path)
            h.update(("L|%s|%s\n" % (rel, target)).encode("utf-8", "replace"))
            if not target.startswith(root_real + os.sep) and not vendor:
                out.append(Finding("SYMLINK-ESCAPE", "MEDIUM", "Symlink points outside the component",
                                   path, 0, "-> " + target,
                                   "Can expose or overwrite files elsewhere on disk."))
            continue
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if size > MAX_TEXT:
            stats["skipped_large"] += 1
            h.update(("S|%s|%d\n" % (rel, size)).encode("utf-8", "replace"))
            continue
        try:
            with open(path, "rb") as f:
                data = f.read()
        except (OSError, IOError):
            continue
        h.update(("F|%s|" % rel).encode("utf-8", "replace") + hashlib.sha256(data).digest())
        head = data[:4096]
        if head.startswith(BIN_MAGIC) and not vendor:
            stats["binaries"] += 1
            if head[:2] != b"MZ" or rel.lower().endswith((".exe", ".dll")):
                out.append(Finding("NATIVE-BINARY", "MEDIUM" if context == "skill" else "LOW",
                                   "Ships a compiled executable (cannot be reviewed)",
                                   path, 0, rel, "Verify where it comes from / is it signed."))
            continue
        kind = file_kind(path, context, head, rel, vendor)
        if kind is None:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = data.decode("latin-1")
            if "\x00" in text[:4096]:
                continue
        stats["scanned"] += 1
        base = os.path.basename(path).lower()
        scan_text(text, kind, path, vendor=vendor, findings=out, rel=rel)
        if base in ("skill.md",) or (context in ("skill",) and base.endswith(".md")) or \
                rel.replace(os.sep, "/").startswith(("commands/", "agents/")):
            skill_checks(text, path, out)
        if base == "package.json" and not vendor:
            package_json_checks(text, path, out)
        elif base.endswith(".pth"):
            pth_check(text, path, out)
        elif base == "setup.py" and not vendor:
            setup_py_check(text, path, out)
    return out, h.hexdigest(), stats
