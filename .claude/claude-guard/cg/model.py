"""Core data types. Python 3.8+ stdlib only."""
import os

SEV_ORDER = {"INFO": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4}
SEV_NAMES = {v: k for k, v in SEV_ORDER.items()}

VERDICT = {
    4: "DANGEROUS",
    3: "SUSPICIOUS",
    2: "CAUTION",
    1: "OK",
    0: "CLEAN",
    -1: "CLEAN",
}

HOME = os.path.expanduser("~")
GUARD_HOME = os.environ.get("CLAUDE_GUARD_HOME", os.path.join(HOME, ".claude-guard"))


def sev(name):
    return SEV_ORDER.get(name, 0)


def short_path(p):
    if not p:
        return ""
    if p.startswith(HOME + os.sep):
        return "~" + p[len(HOME):]
    return p


class Finding(object):
    __slots__ = ("rule", "severity", "title", "file", "line", "snippet",
                 "advice", "count", "suppressed")

    def __init__(self, rule, severity, title, file="", line=0, snippet="",
                 advice="", count=1):
        self.rule = rule
        self.severity = severity
        self.title = title
        self.file = file
        self.line = line
        self.snippet = snippet
        self.advice = advice
        self.count = count
        self.suppressed = False

    @property
    def level(self):
        return sev(self.severity)

    def to_dict(self):
        d = {k: getattr(self, k) for k in self.__slots__}
        d["file"] = short_path(self.file)
        return d


class Component(object):
    """Anything that can inject code or instructions into Claude."""
    __slots__ = ("kind", "name", "source", "root", "config", "scope", "extra")

    def __init__(self, kind, name, source="", root=None, config=None,
                 scope="", extra=None):
        self.kind = kind          # skill, plugin, mcp, extension, agent, command, ...
        self.name = name
        self.source = source      # file where it is declared / installed
        self.root = root          # directory (or file) with its code/instructions
        self.config = config      # dict for MCP servers / settings
        self.scope = scope        # desktop, code-user, code-project, plugin:<x>, ...
        self.extra = extra or {}

    @property
    def id(self):
        s = "%s:%s" % (self.kind, self.name)
        if self.scope:
            s += "@" + self.scope
        return s

    def to_dict(self):
        return {
            "id": self.id, "kind": self.kind, "name": self.name,
            "scope": self.scope, "source": short_path(self.source),
            "root": short_path(self.root or ""),
        }


class Result(object):
    def __init__(self, component, findings, fingerprint="", meta=None):
        self.component = component
        self.findings = findings
        self.fingerprint = fingerprint
        self.meta = meta or {}

    @property
    def active(self):
        return [f for f in self.findings if not f.suppressed]

    @property
    def worst(self):
        lv = [f.level for f in self.active]
        return max(lv) if lv else -1

    @property
    def verdict(self):
        return VERDICT[self.worst]

    def counts(self):
        c = {}
        for f in self.active:
            c[f.severity] = c.get(f.severity, 0) + 1
        return c

    def to_dict(self):
        d = self.component.to_dict()
        d.update({
            "verdict": self.verdict,
            "worst": SEV_NAMES.get(self.worst, "NONE"),
            "fingerprint": self.fingerprint,
            "counts": self.counts(),
            "findings": [f.to_dict() for f in sorted(
                self.findings, key=lambda x: -x.level)],
            "meta": self.meta,
        })
        return d
