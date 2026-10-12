import Foundation

/// One job line of a user crontab.
public struct ProtectionCronEntry: Sendable, Hashable {
    /// The exact original line.
    public var line: String
    /// "*/5 * * * *" or "@reboot".
    public var schedule: String
    public var command: String

    public init(line: String, schedule: String, command: String) {
        self.line = line
        self.schedule = schedule
        self.command = command
    }
}

/// Parses and edits `crontab -l` output.
public enum ProtectionCron {
    /// Job lines of a crontab (comments, blank lines and VAR=value lines are skipped).
    public static func entries(in text: String) -> [ProtectionCronEntry] {
        var result: [ProtectionCronEntry] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("@") {
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { continue }
                result.append(ProtectionCronEntry(line: raw, schedule: String(parts[0]),
                                                  command: String(parts[1]).trimmingCharacters(in: .whitespaces)))
                continue
            }
            // Environment assignment (NAME=value) has no schedule fields.
            if let eq = line.firstIndex(of: "="), !line[..<eq].contains(" "), !line[..<eq].contains("\t") { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 6 else { continue }
            let schedule = fields.prefix(5).joined(separator: " ")
            let command = fields.dropFirst(5).joined(separator: " ")
            result.append(ProtectionCronEntry(line: raw, schedule: schedule, command: command))
        }
        return result
    }

    /// The crontab text with every line in `remove` taken out (exact line match).
    public static func removing(_ remove: Set<String>, from text: String) -> String {
        let kept = text.components(separatedBy: "\n").filter { !remove.contains($0) }
        var output = kept.joined(separator: "\n")
        if !output.isEmpty && !output.hasSuffix("\n") { output += "\n" }
        return output
    }

    /// Text `crontab -l` prints when the user has no crontab.
    public static func isEmptyCrontabMessage(_ text: String) -> Bool {
        text.lowercased().contains("no crontab for")
    }
}

/// Parses the outputs of macOS's built-in security status tools.
public enum ProtectionAppleSecurityParser {
    /// `spctl --status` → "assessments enabled".
    public static func gatekeeperEnabled(_ output: String) -> Bool? {
        let lower = output.lowercased()
        if lower.contains("assessments enabled") { return true }
        if lower.contains("assessments disabled") { return false }
        return nil
    }

    /// `csrutil status` → "System Integrity Protection status: enabled."
    public static func sipEnabled(_ output: String) -> Bool? {
        let lower = output.lowercased()
        guard let range = lower.range(of: "status:") else { return nil }
        let rest = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("enabled") { return true }
        if rest.hasPrefix("disabled") { return false }
        return nil
    }

    /// `fdesetup status` → "FileVault is On."
    public static func fileVaultOn(_ output: String) -> Bool? {
        let lower = output.lowercased()
        if lower.contains("filevault is on") { return true }
        if lower.contains("filevault is off") { return false }
        if lower.contains("encryption in progress") || lower.contains("decryption in progress") { return true }
        return nil
    }

    /// `socketfilterfw --getglobalstate` → "Firewall is enabled. (State = 1)".
    public static func firewallEnabled(_ output: String) -> Bool? {
        let lower = output.lowercased()
        if lower.contains("firewall is enabled") || lower.contains("state = 1") || lower.contains("state = 2") { return true }
        if lower.contains("firewall is disabled") || lower.contains("state = 0") { return false }
        return nil
    }

    /// `CFBundleShortVersionString` of an XProtect bundle Info.plist.
    public static func bundleVersion(plistData: Data) -> String? {
        guard let object = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = object as? [String: Any] else { return nil }
        return (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String)
    }

    /// Numeric comparison of dotted versions ("5297" vs "5310", "2.1.10" vs "2.1.9").
    public static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// macOS's own protection layers, as shown on the Protection hub.
public struct ProtectionAppleStatus: Sendable, Equatable {
    public var xprotectVersion: String?
    public var xprotectUpdated: Date?
    public var gatekeeperEnabled: Bool?
    public var sipEnabled: Bool?
    public var fileVaultOn: Bool?
    public var firewallEnabled: Bool?

    public init(xprotectVersion: String? = nil, xprotectUpdated: Date? = nil, gatekeeperEnabled: Bool? = nil,
                sipEnabled: Bool? = nil, fileVaultOn: Bool? = nil, firewallEnabled: Bool? = nil) {
        self.xprotectVersion = xprotectVersion
        self.xprotectUpdated = xprotectUpdated
        self.gatekeeperEnabled = gatekeeperEnabled
        self.sipEnabled = sipEnabled
        self.fileVaultOn = fileVaultOn
        self.firewallEnabled = firewallEnabled
    }

    /// Layers that are known to be off.
    public var disabledLayers: [String] {
        var out: [String] = []
        if gatekeeperEnabled == false { out.append("Gatekeeper") }
        if sipEnabled == false { out.append("System Integrity Protection") }
        if fileVaultOn == false { out.append("FileVault") }
        if firewallEnabled == false { out.append("Firewall") }
        return out
    }
}
