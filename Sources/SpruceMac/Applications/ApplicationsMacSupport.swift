import AppKit
import Foundation
import SpruceCore

/// A value guarded by a lock, for engine state touched from several tasks.
final class ApplicationsLocked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func update<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Small helpers shared by the Applications engine's parts.
enum ApplicationsMac {

    /// A snapshot of the user's settings, read on the main actor.
    static func settings() async -> SpruceSettings {
        await MainActor.run { SettingsStore.shared.settings }
    }

    /// Runs blocking work on a global queue so it never ties up Swift's cooperative threads.
    static func background<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Runs `body` for every index on several threads and collects the results in order.
    static func concurrentMap<T>(_ count: Int, _ body: (Int) -> T?) -> [T] {
        guard count > 0 else { return [] }
        let results = ApplicationsLocked([T?](repeating: nil, count: count))
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let value = body(index)
            results.update { $0[index] = value }
        }
        return results.current.compactMap { $0 }
    }

    /// Runs a command-line tool with extra environment variables and a timeout.
    /// No shell is involved, so arguments cannot inject commands.
    static func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:],
                    timeout: TimeInterval = 120) async -> Shell.Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                for (key, value) in environment { env[key] = value }
                process.environment = env
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Shell.Result(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: Shell.Result(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }

    /// Environment for non-interactive Homebrew runs.
    static let brewEnvironment: [String: String] = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_ENV_HINTS": "1",
        "HOMEBREW_NO_ANALYTICS": "1",
        "HOMEBREW_NO_INSTALL_CLEANUP": "1",
        "NONINTERACTIVE": "1",
        "HOMEBREW_COLOR": "0",
        "NO_COLOR": "1",
    ]

    /// Path of the `brew` executable, if Homebrew is installed.
    static var brewPath: String? {
        ApplicationsHomebrew.brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The last non-empty lines of a tool's error output, for failure messages.
    static func tail(_ text: String, lines: Int = 2) -> String {
        let parts = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.suffix(lines).joined(separator: " ")
    }

    /// The current user's numeric id, for `launchctl` domain targets.
    static var uid: uid_t { getuid() }
}
