import Foundation

// YARA rule files the malware scanner runs over the programs it examines: Apple's XProtect
// rules (read from macOS, offline, kept current by Apple) and the extra rules of Spruce's
// downloaded threat list. Both go through the built-in engine (`YaraRuleSet`).

/// A compiled rule file the malware scanner runs.
public struct ProtectionRuleSource: Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Apple's XProtect.yara.
        case appleXProtect
        /// rules.yara of Spruce's downloaded threat list.
        case threatList
        case other
    }

    public static let appleXProtectName = "Apple XProtect"
    public static let threatListName = "Spruce threat list"

    public let kind: Kind
    /// Shown in reasons and in the inspector ("Apple XProtect").
    public let name: String
    public let rules: YaraRuleSet
    /// Where the rules were read from, when they came from a file.
    public let location: String?
    /// Rules that matched one of Spruce's harmless sample files when the source was built.
    /// Such a rule would flag ordinary files, so its matches are ignored.
    public let disabledRules: Set<String>

    /// `checkSamples` runs the rules over a handful of harmless files (empty file, bare
    /// program header, tiny script…) and disables any rule that matches one.
    public init(kind: Kind, name: String? = nil, rules: YaraRuleSet, location: String? = nil, checkSamples: Bool = true) {
        self.kind = kind
        switch kind {
        case .appleXProtect: self.name = name ?? Self.appleXProtectName
        case .threatList: self.name = name ?? Self.threatListName
        case .other: self.name = name ?? (rules.origin.isEmpty ? "Rules" : rules.origin)
        }
        self.rules = rules
        self.location = location
        var disabled: Set<String> = []
        if checkSamples, !rules.isEmpty {
            for sample in ProtectionHarmlessSamples.all {
                for match in rules.scan(sample) { disabled.insert(match.name) }
            }
            let large = ProtectionHarmlessSamples.largeProgram
            for match in rules.scan(large.data, fileSize: large.fileSize) { disabled.insert(match.name) }
        }
        disabledRules = disabled
    }

    /// Apple's XProtect rules.
    public static func appleXProtect(_ rules: YaraRuleSet, location: String? = nil) -> ProtectionRuleSource {
        ProtectionRuleSource(kind: .appleXProtect, rules: rules, location: location)
    }

    /// The downloaded threat list's rules.
    public static func threatList(_ rules: YaraRuleSet, location: String? = nil) -> ProtectionRuleSource {
        ProtectionRuleSource(kind: .threatList, rules: rules, location: location)
    }

    /// Rules that can report a match.
    public var activeRuleCount: Int { max(0, rules.activeRuleCount - disabledRules.count) }

    public var isEmpty: Bool { activeRuleCount == 0 }

    /// Plain lines about rules that are not used, for a diagnostics view.
    public var notes: [String] {
        var lines = rules.warnings
        for skipped in rules.skipped {
            let name = skipped.name.isEmpty ? "A rule at line \(skipped.line)" : "Rule \(skipped.name)"
            lines.append("\(name) isn't used: \(skipped.reason)")
        }
        for rule in disabledRules.sorted() {
            lines.append("Rule \(rule) isn't used: it matches ordinary files.")
        }
        return lines
    }

    /// Matches in already-read file bytes, without disabled rules.
    public func scan(_ data: Data, fileSize: Int) -> [YaraRuleMatch] {
        let matches = rules.scan(data, fileSize: fileSize)
        guard !disabledRules.isEmpty else { return matches }
        return matches.filter { !disabledRules.contains($0.name) }
    }

    // MARK: Apple's file

    /// Where macOS keeps XProtect's YARA rules, newest location first (macOS 15 moved them
    /// to /private/var/protected).
    public static let appleXProtectPaths = [
        "/private/var/protected/xprotect/XProtect.bundle/Contents/Resources/XProtect.yara",
        "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.yara",
    ]

    /// Apple's rule file is a few hundred KB; anything far bigger is not read.
    public static let maxAppleRulesBytes = 16 << 20

    /// Loads Apple's XProtect rules from the first location that has a readable file.
    /// `root` prefixes the paths (tests). Nil when no file could be read or none of its
    /// rules loaded.
    public static func loadAppleXProtect(root: String = "") -> ProtectionRuleSource? {
        for path in appleXProtectPaths.map({ root + $0 }) {
            guard let (data, size) = YaraRuleSet.readPrefix(ofFile: path, maxBytes: maxAppleRulesBytes),
                  size <= maxAppleRulesBytes, !data.isEmpty else { continue }
            let source = ProtectionRuleSource.appleXProtect(YaraRuleSet(data: data, origin: appleXProtectName),
                                                            location: path)
            if !source.isEmpty { return source }
        }
        return nil
    }
}

/// What a rule match means for a finding: the family it names, its category and severity.
public struct ProtectionRuleVerdict: Sendable, Hashable {
    public var hit: ProtectionRuleHit
    public var sourceKind: ProtectionRuleSource.Kind
    /// Family name shown on the finding ("Adload", "XProtect: MACOS.644e18d").
    public var familyName: String
    /// The catalog family the rule names, when it names one.
    public var familyID: String?
    public var category: ThreatCategory
    public var severity: ThreatSeverity

    /// "Matches Apple's XProtect rule for MACOS.ADLOAD.D".
    public var reason: String { reason(aboutProgram: false) }

    /// The reason, worded for a startup job when `aboutProgram` ("The program it starts
    /// matches …").
    public func reason(aboutProgram: Bool) -> String {
        let rule: String
        switch sourceKind {
        case .appleXProtect: rule = "Apple's XProtect rule for \(hit.label)"
        case .threatList: rule = "the Spruce threat list rule for \(hit.label)"
        case .other: rule = "the \(hit.source) rule for \(hit.label)"
        }
        return aboutProgram ? "The program it starts matches \(rule)" : "Matches \(rule)"
    }
}

/// Turns rule matches into families and categories.
public enum ProtectionRuleClassifier {
    /// Lowest severity of a rule match.
    public static let minimumSeverity: ThreatSeverity = .high

    public static func verdict(for match: YaraRuleMatch, source: ProtectionRuleSource,
                               catalog: ProtectionThreatCatalog) -> ProtectionRuleVerdict {
        let hit = ProtectionRuleHit(source: source.name, rule: match.name, detail: match.description)
        var verdict = ProtectionRuleVerdict(hit: hit, sourceKind: source.kind, familyName: "", familyID: nil,
                                            category: .malware, severity: minimumSeverity)

        // Threat list rules may say what they detect.
        var metaCategory: ThreatCategory?
        var metaSeverity: ThreatSeverity?
        if source.kind != .appleXProtect {
            if let id = text(match, "family")?.lowercased(), let family = catalog.family(id: id) {
                apply(family, to: &verdict)
            } else if let name = text(match, "family_name") ?? text(match, "family") {
                verdict.familyName = name
            }
            metaCategory = text(match, "category").flatMap(category(named:))
            metaSeverity = text(match, "severity").flatMap(severity(named:))
        }

        if verdict.familyName.isEmpty {
            let tokens = words(in: match.description ?? "") + words(in: match.name)
            if let id = tokens.lazy.compactMap({ catalogKeywords[$0] }).first, let family = catalog.family(id: id) {
                apply(family, to: &verdict)
            } else if let named = tokens.lazy.compactMap({ otherFamilies[$0] }).first {
                verdict.familyName = named.name
                verdict.category = named.category
            } else {
                let label = hit.label
                verdict.familyName = source.kind == .appleXProtect ? "XProtect: \(label)" : label
                let hints = tokens + match.tags.map { $0.lowercased() }
                if let category = hints.lazy.compactMap({ categoryKeywords[$0] }).first {
                    verdict.category = category
                }
            }
        }
        if let metaCategory { verdict.category = metaCategory }
        if let metaSeverity { verdict.severity = metaSeverity } else { verdict.severity = max(verdict.severity, minimumSeverity) }
        return verdict
    }

    private static func apply(_ family: ProtectionThreatFamily, to verdict: inout ProtectionRuleVerdict) {
        verdict.familyName = family.name
        verdict.familyID = family.id
        verdict.category = family.category
        verdict.severity = max(family.severity, minimumSeverity)
    }

    private static func text(_ match: YaraRuleMatch, _ key: String) -> String? {
        guard case .text(let value)? = match.meta(key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func category(named raw: String) -> ThreatCategory? {
        let lower = raw.lowercased()
        return ThreatCategory.allCases.first { $0.rawValue.lowercased() == lower }
    }

    static func severity(named raw: String) -> ThreatSeverity? {
        let lower = raw.lowercased()
        return ThreatSeverity.allCases.first { $0.label.lowercased() == lower }
    }

    /// Lowercase alphanumeric words ("XProtect_MACOS_ADLOAD_D" → xprotect, macos, adload, d).
    static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) || !$0.isASCII }).map(String.init)
    }

    /// Words naming a family of the built-in catalog.
    static let catalogKeywords: [String: String] = [
        "adload": "adload", "pirrit": "pirrit", "bundlore": "bundlore", "shlayer": "shlayer", "zshlayer": "zshlayer",
        "genieo": "genieo", "chromeloader": "chromeloader", "convuster": "convuster", "maxofferdeal": "maxofferdeal",
        "mughthesec": "mughthesec", "hydromac": "hydromac", "searchprotect": "searchprotect", "conduit": "searchprotect",
        "vsearch": "vsearch", "trovi": "vsearch", "mami": "mami", "amos": "amos", "atomicstealer": "amos",
        "banshee": "banshee", "cuckoo": "cuckoo", "macsync": "macsync", "odyssey": "odyssey", "poseidon": "poseidon",
        "realst": "realst", "xloader": "xloader", "evilquest": "evilquest", "thiefquest": "evilquest",
        "keranger": "keranger", "loudminer": "loudminer", "osaminer": "osaminer", "ppminer": "ppminer",
        "fruitfly": "fruitfly", "quimitchin": "fruitfly", "eleanor": "eleanor", "coldroot": "coldroot", "mokes": "mokes",
        "calisto": "calisto", "proton": "proton", "dazzlespy": "dazzlespy", "dok": "dok", "cloudmensis": "cloudmensis",
        "jokerspy": "jokerspy", "rustbucket": "rustbucket", "windtail": "windtail", "geacon": "geacon",
        "silversparrow": "silversparrow", "xcsset": "xcsset", "advancedmaccleaner": "advancedmaccleaner",
        "macmechanic": "macmechanic",
    ]

    /// Words naming other well-known families.
    static let otherFamilies: [String: (name: String, category: ThreatCategory)] = [
        "installcore": ("InstallCore", .adware),
        "crossrider": ("Crossrider", .adware),
        "spigot": ("Spigot", .adware),
        "vidinstaller": ("VidInstaller", .adware),
        "flashback": ("Flashback", .trojan),
        "keysteal": ("KeySteal", .stealer),
        "xagent": ("XAgent", .backdoor),
        "macma": ("Macma", .backdoor),
        "lamepyre": ("LamePyre", .trojan),
        "wirelurker": ("WireLurker", .trojan),
        "xcodeghost": ("XcodeGhost", .trojan),
        "hiddenlotus": ("HiddenLotus", .backdoor),
        "olyx": ("Olyx", .backdoor),
        "dolittle": ("DoLittle", .backdoor),
    ]

    /// Words hinting at a category when the family is unknown (also used for rule tags).
    static let categoryKeywords: [String: ThreatCategory] = [
        "adware": .adware, "hijacker": .browserHijacker, "browserhijacker": .browserHijacker,
        "stealer": .stealer, "infostealer": .stealer, "pws": .stealer, "passwordstealer": .stealer,
        "backdoor": .backdoor, "rat": .backdoor, "spyware": .spyware, "keylogger": .spyware,
        "trojan": .trojan, "dropper": .dropper, "downloader": .dropper, "loader": .dropper,
        "miner": .miner, "coinminer": .miner, "cryptominer": .miner, "ransom": .ransomware, "ransomware": .ransomware,
    ]
}

/// Ordinary files no sensible malware rule matches (see `ProtectionRuleSource.disabledRules`).
enum ProtectionHarmlessSamples {
    /// The start of a bigger program (a 64-bit header, then zeros: 256 KB read of a 1 MB
    /// file), so a rule that only looks at the header and the size is switched off too.
    static let largeProgram: (data: Data, fileSize: Int) = (
        Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 0x03, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00]
            + [UInt8](repeating: 0, count: (256 << 10) - 16)),
        1 << 20
    )

    static let all: [Data] = {
        var samples: [Data] = []
        samples.append(Data())
        // Bare 64-bit and universal program headers followed by zeros.
        samples.append(Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01] + [UInt8](repeating: 0, count: 4088)))
        samples.append(Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02] + [UInt8](repeating: 0, count: 4088)))
        samples.append(Data([0xCE, 0xFA, 0xED, 0xFE] + [UInt8](repeating: 0, count: 1020)))
        // A Windows program stub.
        var pe = [UInt8](repeating: 0, count: 0x200)
        pe[0] = 0x4D
        pe[1] = 0x5A
        pe[0x3C] = 0x80
        pe[0x80] = 0x50
        pe[0x81] = 0x45
        samples.append(Data(pe))
        // Tiny scripts, text and a property list.
        samples.append(Data("#!/bin/sh\nexit 0\n".utf8))
        samples.append(Data("#!/bin/zsh\necho \"Hello\"\n".utf8))
        samples.append(Data("Hello\n".utf8))
        samples.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleIdentifier</key>
        \t<string>com.example.app</string>
        </dict>
        </plist>

        """.utf8))
        // A zip header, a page of zeros and a page of 0xFF.
        samples.append(Data([0x50, 0x4B, 0x03, 0x04] + [UInt8](repeating: 0, count: 1020)))
        samples.append(Data(repeating: 0, count: 4096))
        samples.append(Data(repeating: 0xFF, count: 4096))
        // Deterministic noise.
        var state: UInt64 = 0x5DEECE66D
        var noise = [UInt8](repeating: 0, count: 16 * 1024)
        for index in noise.indices {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            noise[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        samples.append(Data(noise))
        return samples
    }()
}
