import AppKit
import Darwin
import Foundation
import SpruceCore

/// Cancellation flag shared between an async task and blocking scanner work.
final class ProtectionCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Lock-protected value (engine results are written by scans and read by the UI).
final class ProtectionLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var current: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    func update(_ transform: (inout Value) -> Void) {
        lock.lock()
        transform(&storage)
        lock.unlock()
    }
}

/// Small macOS helpers shared by the Protection engines.
enum ProtectionMac {
    /// Runs blocking work on a GCD queue (long scans stay off the main thread and the
    /// cooperative pool). Cancelling the calling task flips the flag the work polls.
    static func runBlocking<T: Sendable>(_ work: @escaping @Sendable (ProtectionCancelFlag) throws -> T) async throws -> T {
        let flag = ProtectionCancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try work(flag))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    /// The current settings, read on the main thread (the settings store is UI state).
    static func settings() async -> SpruceSettings {
        await MainActor.run { SettingsStore.shared.settings }
    }

    /// Adds an Activity entry on the main thread.
    static func record(_ entry: ActivityEntry) async {
        await MainActor.run { HistoryStore.shared.record(entry) }
    }

    /// Runs a tool, feeding `input` to its standard input (no shell involved).
    static func run(_ executable: String, _ arguments: [String], input: Data, timeout: TimeInterval = 30) async -> Shell.Result {
        await withCheckedContinuation { (continuation: CheckedContinuation<Shell.Result, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let inPipe = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardInput = inPipe
                process.standardOutput = outPipe
                process.standardError = errPipe
                // A tool that exits early must not take the app down with SIGPIPE.
                _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Shell.Result(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                try? inPipe.fileHandleForWriting.write(contentsOf: input)
                try? inPipe.fileHandleForWriting.close()
                let errData = ProtectionLocked(Data())
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errData.current = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: Shell.Result(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData.current, as: UTF8.self)
                ))
            }
        }
    }

    /// The per-user Darwin cache folder's Quick Look thumbnail cache.
    static func quickLookCachePath() -> String? {
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length) > 0 else { return nil }
        let folder = String(cString: buffer)
        guard !folder.isEmpty else { return nil }
        return (folder as NSString).appendingPathComponent("com.apple.QuickLook.thumbnailcache")
    }

    /// Force-quits running apps whose bundle is (or contains) one of `bundlePaths`, then
    /// waits up to three seconds for them to exit. Returns how many were asked to quit.
    @MainActor
    static func forceQuitApps(inside bundlePaths: [String]) async -> Int {
        let roots = bundlePaths.map { ($0 as NSString).standardizingPath }
        guard !roots.isEmpty else { return 0 }
        let own = ProcessInfo.processInfo.processIdentifier
        let targets = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != own else { return false }
            let paths = [app.bundleURL?.standardizedFileURL.path, app.executableURL?.standardizedFileURL.path].compactMap { $0 }
            return paths.contains { path in roots.contains { path == $0 || path.hasPrefix($0 + "/") } }
        }
        for app in targets { app.forceTerminate() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, targets.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return targets.count
    }

    /// Short failure text from a tool's output.
    static func message(from result: Shell.Result, fallback: String) -> String {
        let text = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fallback }
        return String(text.split(separator: "\n").first ?? Substring(fallback))
    }
}
