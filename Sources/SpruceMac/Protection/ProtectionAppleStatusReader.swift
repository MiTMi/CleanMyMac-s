import Foundation
import SpruceCore

/// Reads the state of macOS's built-in protection (read-only; Spruce never changes it).
enum ProtectionAppleStatusReader {
    /// XProtect signature bundles: the live copy on macOS 15+ and the classic location.
    static let xprotectPlists = [
        "/private/var/protected/xprotect/XProtect.bundle/Contents/Info.plist",
        "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
    ]

    static func read() async -> ProtectionAppleStatus {
        async let gatekeeper = Shell.run("/usr/sbin/spctl", ["--status"], timeout: 10)
        async let sip = Shell.run("/usr/bin/csrutil", ["status"], timeout: 10)
        async let fileVault = Shell.run("/usr/bin/fdesetup", ["status"], timeout: 10)
        async let firewall = Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], timeout: 10)
        let xprotect = await readXProtect()
        let gk = await gatekeeper
        let integrity = await sip
        let vault = await fileVault
        let wall = await firewall
        return ProtectionAppleStatus(
            xprotectVersion: xprotect.version,
            xprotectUpdated: xprotect.date,
            gatekeeperEnabled: ProtectionAppleSecurityParser.gatekeeperEnabled(gk.stdout + "\n" + gk.stderr),
            sipEnabled: ProtectionAppleSecurityParser.sipEnabled(integrity.stdout + "\n" + integrity.stderr),
            fileVaultOn: ProtectionAppleSecurityParser.fileVaultOn(vault.stdout + "\n" + vault.stderr),
            firewallEnabled: ProtectionAppleSecurityParser.firewallEnabled(wall.stdout + "\n" + wall.stderr)
        )
    }

    /// `xprotect version` on macOS 15+, falling back to (or bettered by) the bundle's Info.plist.
    static func readXProtect() async -> (version: String?, date: Date?) {
        var version: String?
        var date: Date?
        let tool = "/usr/bin/xprotect"
        if FileManager.default.isExecutableFile(atPath: tool) {
            let result = await Shell.run(tool, ["version"], timeout: 15)
            if result.status == 0 {
                let parsed = ProtectionXProtectParser.parseVersionCommand(result.stdout)
                version = parsed.version
                date = parsed.installed
            }
        }
        for plist in xprotectPlists {
            guard let data = FileManager.default.contents(atPath: plist),
                  let found = ProtectionAppleSecurityParser.bundleVersion(plistData: data) else { continue }
            let modified = (try? FileManager.default.attributesOfItem(atPath: plist))?[.modificationDate] as? Date
            if let current = version {
                if ProtectionAppleSecurityParser.isVersion(found, newerThan: current) {
                    version = found
                    date = modified
                } else if found == current, date == nil {
                    date = modified
                }
            } else {
                version = found
                date = modified
            }
        }
        return (version, date)
    }
}
