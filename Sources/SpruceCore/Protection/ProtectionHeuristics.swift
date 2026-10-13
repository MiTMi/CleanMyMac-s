import Foundation

/// Accumulates heuristic signals into a score with human-readable reasons.
public struct ProtectionScore: Sendable, Equatable {
    public private(set) var value: Int = 0
    public private(set) var reasons: [(points: Int, text: String)] = []
    public private(set) var category: ThreatCategory = .suspicious

    public init() {}

    public mutating func add(_ points: Int, _ reason: String) {
        guard points != 0 else { return }
        value += points
        if points > 0 { reasons.append((points, reason)) }
    }

    /// Raises the category when a behaviour clearly points at a threat class.
    public mutating func suggest(_ category: ThreatCategory) {
        if self.category == .suspicious { self.category = category }
    }

    /// Reasons, strongest first.
    public var sortedReasons: [String] {
        reasons.sorted { $0.points > $1.points }.map(\.text)
    }

    public static func == (lhs: ProtectionScore, rhs: ProtectionScore) -> Bool {
        lhs.value == rhs.value && lhs.sortedReasons == rhs.sortedReasons && lhs.category == rhs.category
    }
}

/// Behavioural rules for persistence items and loose executables.
public enum ProtectionHeuristics {

    // MARK: Locations

    /// Hidden folders in the home folder that developer tools legitimately use for programs.
    public static let developerDotFolders: Set<String> = [
        ".cargo", ".rustup", ".local", ".bun", ".deno", ".nvm", ".volta", ".pyenv", ".rbenv", ".asdf", ".mise",
        ".sdkman", ".orbstack", ".colima", ".lima", ".docker", ".rd", ".dotnet", ".gem", ".npm", ".npm-global",
        ".yarn", ".pnpm", ".config", ".vscode", ".vscode-insiders", ".cursor", ".windsurf", ".zed", ".jenv",
        ".goenv", ".nodenv", ".fnm", ".pub-cache", ".gradle", ".m2", ".android", ".swiftpm", ".mint", ".conda",
        ".miniconda3", ".oh-my-zsh", ".zinit", ".tmux", ".vim", ".emacs.d", ".ollama", ".kube", ".terraform.d",
        ".fly", ".wasmtime", ".wasmer", ".foundry", ".solana", ".bin", ".cache", ".claude", ".codex",
        ".gemini", ".copilot", ".ghcup", ".opam", ".nix-profile", ".nix-defexpr", ".juliaup", ".julia",
        ".elan", ".rye", ".poetry", ".pixi", ".uv", ".hermit", ".tfenv", ".pulumi", ".aws", ".azure",
    ]

    /// Package managers' install prefixes (their services are ad-hoc signed by design).
    public static let packageManagerPrefixes: [String] = [
        "/opt/homebrew/", "/usr/local/Cellar/", "/usr/local/opt/", "/usr/local/Homebrew/",
        "/usr/local/Caskroom/", "/opt/local/", "/nix/", "/opt/pkg/",
    ]

    public static let temporaryFolders: [String] = ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/"]
    public static let sharedFolder = "/Users/Shared/"

    /// Where a path sits, from a threat-hunting point of view.
    public struct PathTraits: Sendable, Equatable {
        public var inTemporaryFolder = false
        public var inSharedFolder = false
        /// A path component (below home or Application Support) starts with ".", excluding developer folders.
        public var inHiddenFolder = false
        public var isHiddenFile = false
        public var inHomeRoot = false
        public var inDeveloperFolder = false
        public var inPackageManager = false
        public var inApplicationSupport = false
        public var inHiddenApplicationSupportFolder = false
    }

    /// Analyses `path` (real path) given the home folder and scanned root.
    public static func traits(of path: String, space: ProtectionPathSpace) -> PathTraits {
        var t = PathTraits()
        let logical = space.logical(path)
        let name = (path as NSString).lastPathComponent
        t.isHiddenFile = name.hasPrefix(".") && name.count > 1
        t.inTemporaryFolder = temporaryFolders.contains { logical.hasPrefix($0) }
        t.inSharedFolder = logical.hasPrefix(sharedFolder)
        t.inPackageManager = packageManagerPrefixes.contains { logical.hasPrefix($0) }

        if logical.hasPrefix("~/") {
            let components = logical.dropFirst(2).split(separator: "/").map(String.init)
            t.inHomeRoot = components.count == 1
            if let first = components.first, first.hasPrefix("."), components.count > 1 {
                if developerDotFolders.contains(first) {
                    t.inDeveloperFolder = true
                } else {
                    t.inHiddenFolder = true
                }
            }
            // Hidden folders deeper down (excluding the file name itself).
            if !t.inDeveloperFolder, components.count > 2 {
                for component in components.dropFirst().dropLast() where component.hasPrefix(".") && component.count > 1 {
                    t.inHiddenFolder = true
                }
            }
        }
        let supportRoots = ["~/Library/Application Support/", "/Library/Application Support/"]
        for root in supportRoots where logical.hasPrefix(root) {
            t.inApplicationSupport = true
            let rest = logical.dropFirst(root.count).split(separator: "/")
            if rest.count > 1, let first = rest.first, first.hasPrefix(".") {
                t.inHiddenApplicationSupportFolder = true
                t.inHiddenFolder = true
            }
        }
        return t
    }

    // MARK: Names

    /// True when a name looks machine-generated (random letters, mixed case with digits…).
    /// Dictionary-word names ("ElementarySearch", "MapperState") are not random.
    public static func looksRandom(_ rawName: String) -> Bool {
        var name = rawName
        for ext in [".plist", ".app", ".sh", ".py", ".service", ".system", ".agent", ".daemon", ".helper"] where name.lowercased().hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
        }
        let tokens = name.split(whereSeparator: { ".-_ @".contains($0) }).map(String.init)
        let ignored: Set<String> = ["com", "net", "org", "io", "co", "app", "www", "plist", "agent", "daemon",
                                    "helper", "service", "system", "update", "updater", "launcher", "user"]
        for token in tokens where !ignored.contains(token.lowercased()) {
            if tokenLooksRandom(token) { return true }
        }
        return false
    }

    static func tokenLooksRandom(_ token: String) -> Bool {
        let chars = Array(token)
        guard chars.count >= 8 else { return false }
        // UUIDs and long hex strings are generated, but common for legitimate data folders.
        let hex = chars.allSatisfy { $0.isHexDigit }
        if hex { return false }
        let letters = chars.filter(\.isLetter)
        let digits = chars.filter(\.isNumber)
        let uppers = letters.filter(\.isUppercase)
        let lowers = letters.filter(\.isLowercase)

        // Case changes that aren't CamelCase word starts: "wznlVRt83Jsd".
        var caseFlips = 0
        for i in 1..<chars.count where chars[i].isLetter && chars[i - 1].isLetter {
            if chars[i].isUppercase && chars[i - 1].isLowercase { caseFlips += 1 }
            if chars[i].isLowercase && chars[i - 1].isUppercase && i >= 2 && chars[i - 2].isUppercase { caseFlips += 1 }
        }
        // Digits with letters both before and after them: "HPyT0b4Hwxh", "wznlVRt83Jsd".
        let firstLetter = chars.firstIndex(where: { $0.isLetter }) ?? chars.count
        let lastLetter = chars.lastIndex(where: { $0.isLetter }) ?? -1
        var interiorDigits = 0
        for i in chars.indices where chars[i].isNumber && i > firstLetter && i < lastLetter {
            interiorDigits += 1
        }
        let vowelRatio = letters.isEmpty ? 0 : Double(letters.filter { "aeiouyAEIOUY".contains($0) }.count) / Double(letters.count)
        if !uppers.isEmpty && !lowers.isEmpty && interiorDigits >= 1 && caseFlips >= 2 { return true }
        if interiorDigits >= 2 && letters.count >= 6 && (caseFlips >= 1 || vowelRatio < 0.25) { return true }

        // Few vowels / long consonant runs in a purely alphabetic token: "xkqzvbtrmw".
        if digits.isEmpty && letters.count == chars.count {
            let lower = token.lowercased()
            let vowels = lower.filter { "aeiouy".contains($0) }.count
            if Double(vowels) / Double(lower.count) < 0.18 { return true }
            var run = 0
            var longest = 0
            for ch in lower {
                if "aeiouy".contains(ch) { run = 0 } else { run += 1; longest = max(longest, run) }
            }
            if longest >= 6 { return true }
        }
        return false
    }

    // MARK: Launch items

    /// Command fragments that indicate a downloader or obfuscated loader.
    public static let loaderMarkers: [String] = [
        "curl ", "curl\t", "wget ", "base64 -d", "base64 --decode", "base64 -D", "| sh", "|sh", "| bash", "|bash",
        "| zsh", "|zsh", "eval ", "eval(", "exec(", "osascript -e", "nohup ", "chmod +x", "chmod 777", "xattr -c",
        "xattr -d com.apple.quarantine", "/dev/tcp/", "python -c", "python3 -c", "openssl enc -d",
    ]

    /// True when a command downloads something and pipes it straight into a shell/interpreter.
    public static func downloadsAndExecutes(_ text: String) -> Bool {
        let fetches = text.contains("curl") || text.contains("wget")
        let pipes = ["| sh", "|sh", "| bash", "|bash", "| zsh", "|zsh", "| python", "|python", "| osascript", "|osascript"]
            .contains { text.contains($0) }
        return fetches && pipes
    }

    /// Inputs for evaluating one launch job.
    public struct LaunchContext: Sendable {
        public var item: ProtectionLaunchItem
        /// Signing of the payload (program or script).
        public var payloadSigning: ProtectionSigningInfo?
        public var payloadExists: Bool
        public var payloadType: ProtectionFileSniffer.FileType?
        /// Script text when the payload is a small script.
        public var payloadText: String?

        public init(item: ProtectionLaunchItem, payloadSigning: ProtectionSigningInfo?, payloadExists: Bool,
                    payloadType: ProtectionFileSniffer.FileType?, payloadText: String?) {
            self.item = item
            self.payloadSigning = payloadSigning
            self.payloadExists = payloadExists
            self.payloadType = payloadType
            self.payloadText = payloadText
        }
    }

    /// Scores a launch agent/daemon. Returns a zero score for clearly benign items.
    public static func evaluate(_ ctx: LaunchContext, space: ProtectionPathSpace) -> ProtectionScore {
        var score = ProtectionScore()
        let item = ctx.item
        let label = item.label ?? ""
        let fileName = (item.plistPath as NSString).lastPathComponent

        if !item.isValidPlist {
            score.add(35, "Startup file isn't a valid property list — it may be disguised code")
            if looksRandom(fileName) { score.add(15, "Randomly generated file name") }
            return score
        }
        if label.lowercased().hasPrefix("homebrew.mxcl.") { return ProtectionScore() }

        let payload = item.payloadPath
        let isAppleSigned = ctx.payloadSigning?.status == .apple
        let interpreter = item.interpreter

        if let payload {
            if packageManagerPrefixes.contains(where: { space.logical(payload).hasPrefix($0) }) {
                return ProtectionScore()
            }
            if !ctx.payloadExists && item.inlineCommand == nil {
                // A job pointing at a missing program can't run: it's a leftover, not a threat.
                return ProtectionScore()
            }
        }

        // Apple impersonation: com.apple.* outside /System running non-Apple code.
        if label.lowercased().hasPrefix("com.apple.") || fileName.lowercased().hasPrefix("com.apple.") {
            let scriptPayload = interpreter != nil
            if !isAppleSigned || scriptPayload {
                score.add(40, "Pretends to be an Apple service but isn't signed by Apple")
                score.suggest(.trojan)
            }
        }

        if let payload {
            let traits = Self.traits(of: payload, space: space)
            if traits.inTemporaryFolder {
                score.add(35, "Runs a program from a temporary folder")
            }
            if traits.inSharedFolder {
                score.add(30, "Runs a program from the shared users folder")
            }
            if traits.inHiddenApplicationSupportFolder {
                score.add(40, "Runs a program hidden in an invisible Application Support folder")
            } else if traits.inHiddenFolder {
                score.add(35, "Runs a program hidden in an invisible folder")
            }
            if traits.isHiddenFile {
                score.add(traits.inDeveloperFolder ? 0 : 25, "The program itself is an invisible file")
            }
            if traits.inHomeRoot && !traits.isHiddenFile {
                score.add(15, "Runs a program stored loose in your home folder")
            }
            let payloadName = (payload as NSString).lastPathComponent
            if looksRandom(payloadName) { score.add(15, "Program has a randomly generated name") }

            if interpreter == nil, let signing = ctx.payloadSigning {
                let dev = traits.inDeveloperFolder
                switch signing.status {
                case .unsigned: score.add(dev ? 10 : 35, "Program isn't code-signed")
                case .adHoc: score.add(dev ? 5 : 25, "Program is ad-hoc signed (no developer identity)")
                case .invalid: score.add(35, "Program's signature is broken (modified after signing)")
                case .signed, .apple, .unknown: break
                }
                if signing.status == .unsigned || signing.status == .adHoc || signing.status == .invalid {
                    if item.runAtLoad && item.keepAlive { score.add(10, "Starts at login and restarts itself if stopped") }
                }
            }
            if let type = ctx.payloadType, case .appleScript = type, interpreter == nil {
                score.add(20, "Starts a compiled AppleScript directly")
            }
        }

        if let interpreter {
            let inline = item.inlineCommand ?? ""
            let scriptText = ctx.payloadText ?? ""
            let combined = inline + "\n" + scriptText
            let markers = loaderMarkers.filter { combined.contains($0) }
            if !markers.isEmpty {
                score.add(inline.isEmpty ? 30 : 40, "Runs \(interpreter) code that downloads or decodes something (\(markers.prefix(2).joined(separator: ", ").trimmingCharacters(in: .whitespaces)))")
                score.suggest(.dropper)
            }
            if downloadsAndExecutes(combined) {
                score.add(20, "Downloads code and runs it immediately")
            }
            if !inline.isEmpty {
                let mentionsHidden = inline.contains("/.") || inline.contains("~/.")
                let mentionsTemp = temporaryFolders.contains { inline.contains($0) } || inline.contains("/Users/Shared/")
                if mentionsHidden || mentionsTemp {
                    score.add(25, "Inline command uses hidden or temporary files")
                }
            }
            if interpreter == "osascript", payload.map({ traits(of: $0, space: space).inHiddenFolder }) == true {
                score.add(15, "Runs a hidden AppleScript at login")
            }
            if combined.contains("display dialog") && combined.contains("hidden answer") {
                score.add(45, "Script asks for a password in a fake dialog")
                score.suggest(.stealer)
            }
        }

        let text = item.commandText
        if text.contains("--load-extension") {
            score.add(55, "Force-loads a browser extension every time you log in")
            score.suggest(.browserHijacker)
        }
        if text.contains("networksetup"), ["-setwebproxy", "-setsecurewebproxy", "-setautoproxyurl", "-setdnsservers"].contains(where: { text.contains($0) }) {
            score.add(45, "Changes your network proxy or DNS settings")
            score.suggest(.browserHijacker)
        }
        if let domain = ProtectionThreatCatalog.mentionsHijackDomain(text) {
            score.add(45, "Points the browser at a known search-hijack site (\(domain))")
            score.suggest(.browserHijacker)
        }
        for key in item.environment.keys where key.contains("DYLD_INSERT_LIBRARIES") {
            score.add(45, "Injects code into other programs (DYLD_INSERT_LIBRARIES)")
            score.suggest(.trojan)
        }
        if looksRandom(label.isEmpty ? fileName : label) {
            score.add(15, "Startup job has a randomly generated name")
        }
        if label.lowercased() == "com.user.loginscript" {
            score.add(10, "Uses a startup job name seen in Cuckoo infections")
        }
        return score
    }

    // MARK: Loose executables

    /// Scores an executable found outside persistence locations (balanced/deep scans).
    public static func evaluateExecutable(path: String, type: ProtectionFileSniffer.FileType,
                                          signing: ProtectionSigningInfo?, space: ProtectionPathSpace) -> ProtectionScore {
        var score = ProtectionScore()
        let traits = Self.traits(of: path, space: space)
        if traits.inPackageManager || traits.inDeveloperFolder { return score }
        if signing?.status == .apple || signing?.status == .signed { return score }
        let isBinary = type == .machO
        if traits.inTemporaryFolder { score.add(35, "Program stored in a temporary folder") }
        if traits.inSharedFolder { score.add(30, "Program stored in the shared users folder") }
        if traits.inHomeRoot && traits.isHiddenFile {
            score.add(isBinary ? 45 : 35, "Invisible program directly in your home folder")
        } else if traits.inHiddenApplicationSupportFolder {
            score.add(40, "Program hidden in an invisible Application Support folder")
        } else if traits.inHiddenFolder {
            score.add(25, "Program hidden in an invisible folder")
        }
        switch signing?.status {
        case .unsigned?: if isBinary { score.add(20, "Program isn't code-signed") }
        case .adHoc?: if isBinary { score.add(15, "Program is ad-hoc signed (no developer identity)") }
        case .invalid?: score.add(30, "Program's signature is broken (modified after signing)")
        default: break
        }
        if looksRandom((path as NSString).lastPathComponent) { score.add(15, "Randomly generated name") }
        if case .appleScript = type, traits.inHiddenFolder || traits.inTemporaryFolder {
            score.add(15, "Compiled AppleScript in a hidden location")
        }
        return score
    }

    /// Scores a privileged helper tool (root-level helpers should always carry a developer signature).
    public static func evaluateHelper(path: String, signing: ProtectionSigningInfo?) -> ProtectionScore {
        var score = ProtectionScore()
        switch signing?.status {
        case .unsigned?: score.add(45, "Administrator-level helper isn't code-signed")
        case .adHoc?: score.add(40, "Administrator-level helper has no developer identity")
        case .invalid?: score.add(45, "Administrator-level helper's signature is broken")
        default: break
        }
        if looksRandom((path as NSString).lastPathComponent) { score.add(15, "Randomly generated name") }
        return score
    }

    /// Scores a crontab entry.
    public static func evaluateCron(_ entry: ProtectionCronEntry, space: ProtectionPathSpace) -> ProtectionScore {
        var score = ProtectionScore()
        let command = entry.command
        let markers = loaderMarkers.filter { command.contains($0) }
        if !markers.isEmpty {
            score.add(40, "Scheduled command downloads or decodes something (\(markers.prefix(2).joined(separator: ", ").trimmingCharacters(in: .whitespaces)))")
            score.suggest(.dropper)
        }
        if downloadsAndExecutes(command) {
            score.add(20, "Downloads code and runs it immediately")
        }
        if command.contains(space.home + "/.") || command.contains("~/.") || command.contains("$HOME/.") {
            score.add(30, "Runs an invisible file from your home folder")
        }
        if temporaryFolders.contains(where: { command.contains($0) }) || command.contains(sharedFolder) {
            score.add(30, "Runs something from a temporary or shared folder")
        }
        if command.contains("osascript") { score.add(15, "Runs AppleScript on a schedule") }
        if entry.schedule.hasPrefix("@reboot") { score.add(10, "Runs at every startup") }
        return score
    }
}
