"""Human / JSON output."""
import json
import os
import sys

from .model import short_path, SEV_ORDER

COL = {"CRITICAL": "\033[1;41;97m", "HIGH": "\033[1;31m", "MEDIUM": "\033[33m",
       "LOW": "\033[36m", "INFO": "\033[2m", "OK": "\033[32m", "B": "\033[1m", "D": "\033[2m",
       "R": "\033[0m"}
VCOL = {"DANGEROUS": "CRITICAL", "SUSPICIOUS": "HIGH", "CAUTION": "MEDIUM", "OK": "OK", "CLEAN": "OK"}
ICON = {"DANGEROUS": "⛔", "SUSPICIOUS": "⚠️ ", "CAUTION": "🔶", "OK": "✅", "CLEAN": "✅"}


def _c(key, s, color):
    return COL[key] + s + COL["R"] if color else s


def render(results, min_sev="LOW", color=None, show_clean=True, title=None):
    color = sys.stdout.isatty() and not os.environ.get("NO_COLOR") if color is None else color
    floor = SEV_ORDER[min_sev]
    lines = []
    if title:
        lines.append(_c("B", title, color))
    order = sorted(results, key=lambda r: (-r.worst, r.component.kind, r.component.name))
    clean = 0
    for r in order:
        shown = [f for f in r.active if f.level >= floor]
        if not shown and r.worst < 2:
            clean += 1
            if not show_clean:
                continue
        v = r.verdict
        c = r.component
        tag = "  [trusted]" if r.meta.get("trusted") else ""
        chg = "  (%s)" % r.meta["change"] if r.meta.get("change") in ("new", "changed") else ""
        lines.append("%s %s  %s %s%s%s" % (ICON[v], _c(VCOL[v], v.ljust(10), color),
                                          _c("B", "%s:%s" % (c.kind, c.name), color),
                                          _c("D", "[%s]" % c.scope, color) if c.scope else "", chg, tag))
        loc = short_path(c.root or c.source)
        if loc and shown:
            lines.append(_c("D", "     " + loc, color))
        meta = r.meta
        bits = []
        for k in ("version", "published", "weekly_downloads", "stars", "server"):
            if meta.get(k):
                bits.append("%s=%s" % (k, str(meta[k])[:25]))
        if bits and shown:
            lines.append(_c("D", "     " + "  ".join(bits), color))
        for f in sorted(shown, key=lambda x: -x.level)[:25]:
            where = short_path(f.file)
            if where and c.root and f.file == c.root:
                where = os.path.basename(f.file)
            elif where and c.root and f.file.startswith(c.root + os.sep):
                where = os.path.relpath(f.file, c.root)
            loc = "%s%s" % (where, (":%d" % f.line) if f.line else "")
            cnt = " (x%d)" % f.count if f.count > 1 else ""
            lines.append("     %s %s%s  %s" % (_c(f.severity, f.severity[:4].ljust(4), color),
                                               f.title, cnt, _c("D", loc, color)))
            if f.snippet:
                lines.append(_c("D", "          > " + f.snippet, color))
            if f.advice and f.level >= 3:
                lines.append("          " + f.advice)
        if len(shown) > 25:
            lines.append("     ... %d more (use --json)" % (len(shown) - 25))
        sup = len(r.findings) - len(r.active)
        if sup and not r.meta.get("trusted"):
            lines.append(_c("D", "     (%d suppressed by allowlist)" % sup, color))
    if not show_clean and clean:
        lines.append(_c("D", "%d more components clean/low-risk (use --all to list)" % clean, color))
    return "\n".join(lines)


def summary_line(results):
    w = {}
    for r in results:
        w[r.verdict] = w.get(r.verdict, 0) + 1
    parts = ["%d %s" % (w[k], k.lower()) for k in ("DANGEROUS", "SUSPICIOUS", "CAUTION", "OK", "CLEAN") if w.get(k)]
    return "%d components: %s" % (len(results), ", ".join(parts) or "none")


def as_json(results):
    return json.dumps([r.to_dict() for r in results], indent=1, default=str)
