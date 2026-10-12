import AppKit
import Foundation
import SpruceCore

/// Runs the few operations that need root, via a single macOS administrator prompt
/// (`do shell script … with administrator privileges`).
///
/// Design rules (learned from the 2018 CleanMyMac helper vulnerabilities):
/// * No persistent root daemon — nothing stays installed that another process could abuse.
/// * Only fixed commands from `PrivilegedCommand`; nothing is interpolated except paths
///   that have just passed `PathGuard` and are single-quote escaped.
/// * One prompt per batch: commands are joined into one script.
public final class PrivilegedRunner: @unchecked Sendable {
    public static let shared = PrivilegedRunner()

    /// Fixed, audited administrator commands.
    public enum PrivilegedCommand: String, CaseIterable, Sendable {
        case flushDNS
        case purgeMemory
        case reindexSpotlight
        case runPeriodicScripts
        case thinTimeMachineSnapshots
        case rebuildLaunchServices
        case clearFontCaches
        case repairHomePermissions
        case emptySystemTrashes

        /// The exact shell command executed as root.
        public var shell: String {
            switch self {
            case .flushDNS:
                return "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
            case .purgeMemory:
                return "/usr/sbin/purge"
            case .reindexSpotlight:
                return "/usr/bin/mdutil -E /"
            case .runPeriodicScripts:
                return "if [ -x /usr/sbin/periodic ]; then /usr/sbin/periodic daily weekly monthly; fi"
            case .thinTimeMachineSnapshots:
                // Ask the system to reclaim up to 1 TB of purgeable snapshot space, urgency 4 (highest).
                return "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"
            case .rebuildLaunchServices:
                return "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"
            case .clearFontCaches:
                return "/usr/bin/atsutil databases -remove"
            case .repairHomePermissions:
                return "/usr/sbin/diskutil resetUserPermissions / \(getuid())"
            case .emptySystemTrashes:
                return "/bin/rm -rf /Volumes/*/.Trashes/\(getuid())/* 2>/dev/null; true"
            }
        }
    }

    public init() {}

    /// Runs commands as root with one prompt. Returns combined output.
    @discardableResult
    public func run(_ commands: [PrivilegedCommand]) async throws -> String {
        guard !commands.isEmpty else { return "" }
        let script = commands.map { "(\($0.shell))" }.joined(separator: "; ")
        return try await runAsAdministrator(script)
    }

    /// Removes root-owned paths. Every path is re-checked with `PathGuard` (permanent
    /// removal semantics) and must not be a symlink-escaped location.
    public func removePaths(_ paths: [String], guardian: PathGuard = PathGuard()) async throws {
        var safe: [String] = []
        for path in paths {
            let verdict = guardian.check(path, method: .remove)
            guard verdict.isAllowed else { throw SpruceError.blockedPath(path) }
            safe.append(path)
        }
        guard !safe.isEmpty else { return }
        let script = safe.map { "/bin/rm -rf -- \(Self.shellQuote($0))" }.joined(separator: "; ")
        try await runAsAdministrator(script)
    }

    /// Single-quote shell escaping: 'it'\''s'.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private func runAsAdministrator(_ shellScript: String) async throws -> String {
        let escaped = shellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: SpruceError.commandFailed("Could not prepare the administrator command."))
                    return
                }
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    if code == -128 {
                        continuation.resume(throwing: SpruceError.cancelled)
                    } else {
                        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Administrator command failed."
                        continuation.resume(throwing: SpruceError.commandFailed(message))
                    }
                } else {
                    continuation.resume(returning: result.stringValue ?? "")
                }
            }
        }
    }
}

/// Runs a non-privileged command-line tool and captures its output.
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
    }

    /// Executes `executable` with `arguments` (no shell involved, so no injection).
    public static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 60) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                // Drain stderr concurrently so a chatty tool cannot fill the pipe and deadlock.
                var errData = Data()
                let errGroup = DispatchGroup()
                errGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    errGroup.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                errGroup.wait()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}
