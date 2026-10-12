"""Static detection rules.

Each rule only runs when one of its `hints` (lowercase literals) occurs in the
file, which keeps scanning of big node_modules trees fast.

File kinds:
  instr  - markdown/text that Claude reads as instructions (skills, agents,
           commands, CLAUDE.md, rules, output styles)
  desc   - MCP tool/prompt descriptions captured by a live probe
  code   - source code (js/ts/py/...)
  shell  - shell scripts, hook commands, `!` injections
  config - json/yaml/toml configuration
  doc    - README/CHANGELOG/docs of packages (not loaded as instructions)
"""
import re

ALL = {"instr", "desc", "code", "shell", "config"}
EXECUTABLE = {"code", "shell", "instr", "config"}
TEXTUAL = {"instr", "desc"}


class Rule(object):
    __slots__ = ("id", "severity", "title", "rx", "kinds", "hints", "vendor",
                 "advice")

    def __init__(self, id, severity, title, pattern, kinds=ALL, hints=(),
                 vendor=False, advice="", flags=re.I):
        self.id = id
        self.severity = severity
        self.title = title
        self.rx = re.compile(pattern, flags)
        self.kinds = kinds
        self.hints = tuple(h.lower() for h in hints)
        self.vendor = vendor      # also applied inside node_modules/site-packages
        self.advice = advice


R = Rule
RULES = [
    # ---------------------------------------------------------------- IOCs
    R("IOC-SHAI-HULUD", "CRITICAL", "Known npm worm indicator (Shai-Hulud)",
      r"shai[-_ ]?hulud|sha1-hulud|bun_environment\.js|setup_bun\.js",
      ALL | {"doc"}, ("hulud", "bun_environment", "setup_bun"), True,
      "Known self-propagating npm credential-stealing worm. Do not install."),
    R("IOC-S1NGULARITY", "CRITICAL", "Known nx supply-chain attack indicator",
      r"s1ngularity", ALL | {"doc"}, ("s1ngularity",), True,
      "Matches the 2025 nx compromise that abused AI CLIs to steal secrets."),

    # ------------------------------------------- AI agent CLI weaponisation
    R("AI-CLI-ABUSE", "CRITICAL",
      "Invokes an AI coding CLI with safety checks disabled",
      r"(claude|gemini|codex|q)\b[^\n]{0,80}(--dangerously-skip-permissions"
      r"|--yolo|--trust-all-tools|--dangerously-bypass)",
      EXECUTABLE, ("dangerously", "--yolo", "trust-all-tools"), True,
      "Malware uses your own AI agents to search for secrets. Never allow."),
    R("CLAUDE-HOOK-TAMPER", "HIGH",
      "Writes Claude settings/hooks/skills (persistence inside Claude)",
      r"(writeFileSync|writeFile|appendFileSync|appendFile|write_text|copyFileSync|>>|\btee\b|\bcp\b|\bmv\b)"
      r"[^\n]{0,100}\.claude/(settings(\.local)?\.json|skills|agents|commands|hooks)",
      {"code", "shell"}, (".claude/",), False,
      "A component should not silently change Claude's own settings, hooks or skills."),
    R("CLAUDE-MCP-TAMPER", "MEDIUM", "Writes MCP client configuration",
      r"(writeFileSync|writeFile|appendFileSync|write_text|>>|\btee\b|\bcp\b|\bmv\b)"
      r"[^\n]{0,100}(claude_desktop_config\.json|\.claude\.json|\.mcp\.json)",
      {"code", "shell"}, ("claude_desktop_config", ".claude.json", ".mcp.json"), False,
      "Fine for an explicit setup command; suspicious if it happens on its own."),
    R("BYPASS-PERMISSIONS", "HIGH", "Enables bypassPermissions / skip-permissions mode",
      r"bypassPermissions|dangerously-?skip-?permissions|skipDangerousModePermissionPrompt",
      EXECUTABLE, ("bypasspermissions", "skip-permissions", "skippermissions",
                   "skipdangerous"), False,
      "Removes every approval prompt; any injected instruction then runs freely."),

    # ---------------------------------------------------- remote code / shells
    R("PIPE-TO-SHELL", "HIGH", "Downloads and pipes straight into a shell",
      r"(curl|wget|iwr|invoke-webrequest)\b[^\n|]{0,300}\|\s*(sudo\s+)?(ba|z|da|k)?sh\b",
      EXECUTABLE, ("curl", "wget", "iwr", "invoke-webrequest"), False,
      "Runs whatever the server returns at that moment; content can change any time."),
    R("REVERSE-SHELL", "CRITICAL", "Reverse-shell pattern",
      r"/dev/tcp/\d|\bnc(at)?\b[^\n]{0,40}\s-e\s|bash\s+-i\s*>&|socat\b[^\n]{0,60}exec:"
      r"|pty\.spawn\([^)]*\)[^\n]{0,80}socket|socket\.socket\([^\n]{0,200}dup2",
      EXECUTABLE, ("/dev/tcp", "nc ", "ncat", "bash -i", "socat", "pty.spawn", "dup2"),
      True, "Gives a remote attacker an interactive shell on your Mac."),
    R("B64-EXEC", "CRITICAL", "Decodes hidden payload and executes it",
      r"base64\s+(-d|--decode|-D)[^\n]{0,80}\|\s*(ba|z)?sh"
      r"|eval\s*\(\s*(atob|Buffer\.from|unescape|decodeURIComponent)\s*\("
      r"|new\s+Function\s*\(\s*(atob|Buffer\.from)"
      r"|exec\s*\(\s*(base64\.b64decode|zlib\.decompress|marshal\.loads|bytes\.fromhex|codecs\.decode)"
      r"|eval\s*\(\s*compile\s*\(\s*base64",
      EXECUTABLE, ("base64", "atob", "buffer.from", "unescape", "decodeuri",
                   "b64decode", "zlib", "marshal", "fromhex", "codecs"), True,
      "Classic obfuscated-malware loader."),
    R("DOWNLOAD-EXEC", "HIGH", "Fetches remote code and evaluates it",
      r"\b(eval|exec)\s*\(\s*(await\s+)?\(?\s*(await\s+)?(fetch|axios\.get|requests\.get|urllib\.request\.urlopen|urlopen|httpx\.get)\s*\("
      r"|new\s+Function\s*\(\s*await\s+\w+\.text\(\)"
      r"|\bexec\s*\(\s*(requests\.get|urlopen)\([^)]*\)\.(text|read\(\))",
      {"code"}, ("eval", "exec", "function("), False,
      "Executes code that is not in the package you reviewed."),

    # -------------------------------------------------- exfiltration channels
    R("EXFIL-ENDPOINT", "CRITICAL", "Known data-exfiltration / callback service",
      r"webhook\.site|requestbin|pipedream\.net|\.oast\.(fun|me|pro|live|site|online)"
      r"|interact\.sh|burpcollaborator|canarytokens|beeceptor\.com|hookbin\.com",
      ALL, ("webhook.site", "requestbin", "pipedream", ".oast.", "interact.sh",
            "burpcollab", "canarytoken", "beeceptor", "hookbin"), True,
      "These services exist to receive stolen data / prove exploitation."),
    R("EXFIL-CHAT", "HIGH", "Sends data to a Discord webhook / Telegram bot",
      r"discord(app)?\.com/api/webhooks/|api\.telegram\.org/bot",
      ALL, ("discord", "api.telegram.org"), True,
      "Common exfiltration channel for infostealers."),
    R("EXFIL-PASTE", "HIGH", "Uses an anonymous paste / file-drop / tunnel host",
      r"pastebin\.com/(raw|api)|transfer\.sh|0x0\.st|file\.io/|termbin\.com"
      r"|\.ngrok(-free)?\.(io|app|dev)|\.trycloudflare\.com|paste\.ee/",
      ALL, ("pastebin", "transfer.sh", "0x0.st", "file.io", "termbin", "ngrok",
            "trycloudflare", "paste.ee"), True,
      "Throw-away hosts are used to stage payloads or receive stolen data."),
    R("ENV-DUMP", "HIGH", "Serialises the entire environment (all API keys)",
      r"JSON\.stringify\(\s*process\.env\s*\)|json\.dumps\(\s*(dict\()?os\.environ"
      r"|str\(\s*os\.environ\s*\)|\benv\s*\|\s*(curl|nc|base64)|printenv\s*\|\s*(curl|nc)",
      EXECUTABLE, ("process.env", "os.environ", "env", "printenv"), True,
      "Bulk-collecting environment variables is a credential-theft step."),

    # ------------------------------------------------------ credential access
    R("CRED-SSH", "HIGH", "Accesses SSH private keys",
      r"\.ssh/(id_(rsa|ed25519|ecdsa|dsa)|identity)\b|\.ssh/\*|['\"]\.ssh['\"]",
      EXECUTABLE | {"desc"}, (".ssh",), False,
      "No MCP server or skill needs your SSH private keys."),
    R("CRED-CLOUD", "HIGH", "Accesses cloud / git credentials",
      r"\.aws/credentials|\.config/gcloud|\.azure/|\.kube/config|\.docker/config\.json"
      r"|\.git-credentials|\.config/gh/hosts\.yml",
      EXECUTABLE | {"desc"}, (".aws", "gcloud", ".azure", ".kube", ".docker",
                             "git-credentials", "gh/hosts"), False,
      "Token theft enables account takeover and further supply-chain attacks."),
    R("CRED-PKG", "MEDIUM", "Reads package-manager / netrc credentials",
      r"\.npmrc|\.pypirc|\.netrc\b", EXECUTABLE | {"desc"}, (".npmrc", ".pypirc", ".netrc"), False,
      "Normal for HTTP/registry clients; npm worms steal these tokens to spread."),
    R("CRED-KEYCHAIN", "HIGH", "Reads the macOS Keychain",
      r"\bsecurity\s+(find-(generic|internet)-password|dump-keychain|export)\b",
      EXECUTABLE, ("security",), True,
      "Keychain dumping is the core of macOS infostealers."),
    R("KEYCHAIN-API", "MEDIUM", "Reads Keychain items via the Security framework",
      r"\b(SecItemCopyMatching|kSecReturnData)\b", {"code"}, ("secitemcopy", "ksecreturndata"), False,
      "Normal for apps storing their own secrets; unexpected in an MCP server or skill.", flags=0),
    R("CRED-BROWSER", "CRITICAL", "Reads browser passwords / cookies / wallets",
      r"(Google/Chrome|BraveSoftware|Microsoft Edge|Arc/User Data|Chromium)[^\n]{0,80}"
      r"(Login Data|Cookies|Local State|Web Data)|logins\.json|key4\.db"
      r"|Cookies\.binarycookies|nkbihfbeogaeaoehlefnkodbefgpgknn|bfnaelmomeimhlpmgjnjophhpkkoljpa"
      r"|Exodus/exodus\.wallet|\.electrum/wallets|wallet\.dat",
      EXECUTABLE, ("login data", "cookies", "local state", "web data", "logins.json",
                   "key4.db", "binarycookies", "nkbihfbeog", "bfnaelmom", "exodus",
                   "electrum", "wallet.dat"), True,
      "Infostealer behaviour."),
    R("CRED-HISTORY", "MEDIUM", "Reads shell history",
      r"\.(zsh|bash)_history|\.python_history|\.node_repl_history",
      EXECUTABLE | {"desc"}, ("_history",), False,
      "Shell history often contains tokens and passwords."),
    R("CRED-DOTENV", "MEDIUM", "Harvests .env files outside its own project",
      r"(glob|walk|find|rglob|readdir|scandir)\w*\s*\([^\n]{0,120}[\"'/*]\.env(\.\w+)?[\"']|\*\*/\.env\b",
      {"code", "shell"}, (".env",), False,
      "Scanning the disk for .env files is a credential-harvesting technique."),
    R("TRUFFLEHOG", "HIGH", "Runs a secret scanner (used by npm worms)",
      r"trufflehog|gitleaks\s+detect", {"code", "shell", "config"},
      ("trufflehog", "gitleaks"), True,
      "Shai-Hulud style malware runs TruffleHog to find tokens to steal."),
    R("OSASCRIPT-PHISH", "CRITICAL", "Fake password prompt via AppleScript",
      r"display\s+dialog[^\n]{0,200}(hidden\s+answer|password)",
      EXECUTABLE, ("display dialog",), True,
      "AMOS/Atomic-style stealers phish your login password this way."),

    # --------------------------------------------------- persistence / evasion
    R("PERSIST-LAUNCHD", "HIGH", "Installs a LaunchAgent/Daemon or cron job",
      r"Library/Launch(Agents|Daemons)|launchctl\s+(load|bootstrap|submit)|crontab\s+(-l|-)"
      r"|/etc/periodic/|make\s+(new\s+)?login\s+item",
      {"code", "shell", "instr"}, ("launchagents", "launchdaemons", "launchctl",
                                   "crontab", "periodic", "login item"), False,
      "Makes code survive reboots outside of Claude's control."),
    R("PERSIST-API", "MEDIUM", "Uses macOS login-item / privileged-helper APIs",
      r"\b(SMLoginItemSetEnabled|SMAppService|SMJobBless)\b", {"code"},
      ("smloginitem", "smappservice", "smjobbless"), False,
      "Normal for Mac apps with helpers; unexpected in an MCP server or skill.", flags=0),
    R("PERSIST-SHELLRC", "HIGH", "Modifies shell startup files",
      r"(>>|appendFile\w*\(|open\([^)]*['\"]a['\"])[^\n]{0,120}\.(zshrc|zprofile|bashrc|bash_profile|profile)\b",
      {"code", "shell"}, ("zshrc", "zprofile", "bashrc", "bash_profile", "profile"), False,
      "Code injected here runs in every terminal you open."),
    R("GATEKEEPER", "HIGH", "Disables macOS protections (Gatekeeper/SIP/quarantine)",
      r"spctl\s+--master-disable|csrutil\s+disable|xattr\s+-[a-z]*d[a-z]*\s+com\.apple\.quarantine"
      r"|xattr\s+-c\b|defaults\s+write[^\n]{0,60}LSQuarantine",
      EXECUTABLE, ("spctl", "csrutil", "quarantine", "xattr"), True,
      "Removing quarantine lets unsigned downloaded binaries run unchecked."),
    R("ENV-INJECTION", "HIGH", "Code-injection environment variable",
      r"DYLD_INSERT_LIBRARIES|NODE_OPTIONS[\"']?\s*[:=]\s*[\"']?[^\n\"']*--(require|import|loader)"
      r"|PYTHONSTARTUP|LD_PRELOAD|PERL5OPT|RUBYOPT",
      {"config", "shell", "code"}, ("dyld_insert", "node_options", "pythonstartup",
                                    "ld_preload", "perl5opt", "rubyopt"), False,
      "Forces extra code into every process started with this environment."),
    R("SUDO", "MEDIUM", "Requests root privileges", r"\bsudo\s+(-S\s+)?[a-z/]",
      {"shell", "instr", "config"}, ("sudo",), False,
      "Skills/MCP servers should never need root."),
    R("CLIPBOARD-SCREEN", "MEDIUM", "Reads clipboard or captures the screen",
      r"\bpbpaste\b|\bscreencapture\b|CGWindowListCreateImage|NSPasteboard",
      {"code", "shell", "instr"}, ("pbpaste", "screencapture", "cgwindowlist",
                                   "nspasteboard"), False,
      "Fine for clipboard/screenshot tools, otherwise a spying capability."),

    # -------------------------------------------------------- obfuscation
    R("OBF-JSOBFUSCATOR", "HIGH", "javascript-obfuscator output (_0x identifiers)",
      r"(_0x[0-9a-f]{4,6}[^\n]{0,40}){6}", {"code"}, ("_0x",), False,
      "Legitimate open-source MCP servers do not ship obfuscated code."),
    R("OBF-CHARCODES", "MEDIUM", "Builds strings from long char-code lists",
      r"fromCharCode\(\s*(\d{2,3}\s*,\s*){15,}|chr\(\d+\)\s*\+\s*chr\(\d+\)(\s*\+\s*chr\(\d+\)){10,}",
      {"code"}, ("fromcharcode", "chr("), False, "Hides strings from review."),
    R("OBF-HEX", "MEDIUM", "Long hex/unicode-escaped string",
      r"(\\x[0-9a-fA-F]{2}){40,}|(\\u00[0-9a-fA-F]{2}){40,}", {"code"}, ("\\x", "\\u00"),
      False, "Hides strings from review."),
    R("OBF-BLOB", "MEDIUM", "Large embedded base64 blob",
      r"(?<![A-Za-z0-9+/=_-])(?!data:)[A-Za-z0-9+/]{600,}={0,2}(?![A-Za-z0-9+/=])",
      {"code", "shell", "instr"}, (), False,
      "Could be an image/font, could be a packed payload - check what decodes it.",
      flags=0),

    # -------------------------------------------------- prompt injection
    R("PI-OVERRIDE", "HIGH", "Prompt injection: tries to override instructions",
      r"(ignore|disregard|forget|override)\s+(all\s+|any\s+)?(the\s+|your\s+)?"
      r"(previous|prior|above|earlier|system|original)\s+(instructions|prompts?|rules|guidelines|directives)"
      r"|you\s+are\s+no\s+longer\s+(claude|an?\s+assistant)|new\s+system\s+prompt\s*:",
      ALL, ("ignore", "disregard", "forget", "override", "no longer", "system prompt"), False,
      "Text designed to hijack the model."),
    R("PI-CONCEAL", "HIGH", "Prompt injection: hide actions from the user",
      r"(do\s+not|don'?t|never)\s+(tell|inform|mention|reveal|show|notify|alert)\s+(this\s+|it\s+|anything\s+)?(to\s+)?"
      r"the\s+user(?!\s+(to|that|how|which|what|you|it'?s|they|whether|why|where|when)\b)(?!'s)"
      r"|without\s+(telling|informing|notifying|alerting)\s+the\s+user"
      r"|(hide|conceal|keep)\s+(this|it)\s+(secret\s+)?from\s+the\s+user|the\s+user\s+(must|should)\s+not\s+(know|see|be\s+told)",
      ALL, ("user",), False,
      "Legitimate tools have no reason to hide what they do."),
    R("PI-TOOL-POISON", "HIGH", "Tool-poisoning markup / hidden directives",
      r"<\s*(IMPORTANT|SYSTEM|HIDDEN|SECRET)\s*>|\[(SYSTEM|INST)\]|<\|im_start\|>"
      r"|(?i:before\s+(using|calling|you\s+use)\s+(this|any)\s+tool[^\n]{0,80}\b(read|send|include|pass)\b)",
      ALL, ("<", "[system", "[inst", "im_start", "before"), False,
      "Typical of MCP tool-description poisoning attacks.", flags=0),
    R("PI-SHADOW", "HIGH", "Tries to change how OTHER tools behave",
      r"when\s+(the\s+)?(user|assistant|you)\s+(uses?|calls?|invokes?)\s+(the\s+)?[\w-]+\s+tool[^\n]{0,80}(must|always|instead|also)"
      r"|(all|any)\s+(emails?|messages?|requests?)\s+(must|should)\s+(also\s+)?be\s+(sent|forwarded|cc|bcc)",
      ALL, ("tool", "email", "message", "request"), False,
      "Cross-tool shadowing: a server rewriting the behaviour of another server."),
    R("PI-SENSITIVE-ASK", "HIGH", "Instructions request secrets / config files",
      r"\b(read|send|include|pass|upload|attach|forward|post|exfiltrate|leak)\s+[^\n]{0,60}"
      r"(id_rsa|\.ssh/|private\s+key|mcp\.json|claude_desktop_config|credentials?\s+file|"
      r"seed\s+phrase|\.aws/credentials|keychain)",
      TEXTUAL, ("id_rsa", ".ssh/", "private key", "mcp.json", "claude_desktop_config", "credential",
                "seed phrase", "keychain"), False,
      "Instruction text asking the model to move secrets around."),
    R("PI-AUTONOMY", "LOW", "Pushes the model to act without confirmation",
      r"silently\s+(run|execute|install|delete|push|send|upload)"
      r"|without\s+(asking|confirmation|confirming)\s+(for\s+)?(permission|approval|the\s+user)",
      TEXTUAL, ("silently", "without"), False,
      "Removes you from the loop."),
]

# ------------------------------------------------------------ hidden unicode
ZERO_WIDTH = re.compile(u"[​‌‍‎‏⁠-⁤᠎]")
BIDI = re.compile(u"[‪-‮⁦-⁩]")
TAG_CHARS = re.compile(u"[\U000E0000-\U000E007F]+")
HTML_COMMENT = re.compile(r"<!--(.*?)-->", re.S)
IMPERATIVE = re.compile(
    r"\b(ignore|disregard|instructions?\s+(above|below|for)|do\s+not\s+(tell|mention|reveal)|"
    r"assistant\s*:|system\s+prompt|curl\s|wget\s|execute\s|exfiltrat|upload\s|send\s+(it|this|the|all)|"
    r"api[_ ]?key|password|secret|~/\.|"
    r"read\s+~)", re.I)

# ------------------------------------------------- supply-chain reference data
POPULAR_PACKAGES = [
    "@modelcontextprotocol/server-filesystem", "@modelcontextprotocol/server-github",
    "@modelcontextprotocol/server-memory", "@modelcontextprotocol/server-everything",
    "@modelcontextprotocol/server-sequential-thinking", "@modelcontextprotocol/server-puppeteer",
    "@modelcontextprotocol/server-brave-search", "@modelcontextprotocol/server-slack",
    "@modelcontextprotocol/server-postgres", "@modelcontextprotocol/server-gdrive",
    "@modelcontextprotocol/inspector", "@modelcontextprotocol/sdk",
    "@playwright/mcp", "@upstash/context7-mcp", "firecrawl-mcp", "@notionhq/notion-mcp-server",
    "@supabase/mcp-server-supabase", "@stripe/mcp", "@sentry/mcp-server", "mcp-remote",
    "@anthropic-ai/claude-code", "@anthropic-ai/sdk", "@browsermcp/mcp", "figma-developer-mcp",
    "@21st-dev/magic", "@wonderwhy-er/desktop-commander", "exa-mcp-server",
    "@executeautomation/playwright-mcp-server", "@cloudflare/mcp-server-cloudflare",
    "@heroku/mcp-server", "@azure/mcp", "@shopify/dev-mcp", "xcodebuildmcp",
    "@apify/actors-mcp-server", "tavily-mcp", "@perplexity-ai/mcp-server",
    "@linear/mcp-server", "@vercel/mcp-adapter", "chrome-devtools-mcp",
    "mcp-server-fetch", "mcp-server-git", "mcp-server-time", "mcp-server-sqlite",
    "mcp", "fastmcp", "anthropic", "requests", "openai", "uv", "awslabs.core-mcp-server",
]

# Packages publicly confirmed malicious (name-level). Extend in
# ~/.claude-guard/blocklist.json -> {"npm": [...], "pypi": [...]}
KNOWN_BAD = {
    "npm": {"postmark-mcp": "Confirmed malicious MCP server (secretly BCC'd every email, Sep 2025)"},
    "pypi": {},
}

EXFIL_HOSTS_RX = re.compile(
    r"webhook\.site|requestbin|pipedream|oast\.|interact\.sh|ngrok|trycloudflare|"
    r"discord(app)?\.com/api/webhooks|api\.telegram\.org", re.I)

NET_RX = re.compile(
    r"\b(fetch|axios|got|request|urlopen|requests\.(get|post|put)|httpx\.|http\.request|"
    r"https\.request|net\.connect|WebSocket|XMLHttpRequest|curl|wget|socket\.connect|"
    r"aiohttp|URLSession|undici)\b", re.I)
CRED_RX = re.compile(
    r"\.ssh/|\.aws/credentials|\.npmrc|\.git-credentials|\.netrc|find-generic-password|"
    r"Login Data|key4\.db|\.kube/config|\.docker/config\.json|wallet", re.I)
