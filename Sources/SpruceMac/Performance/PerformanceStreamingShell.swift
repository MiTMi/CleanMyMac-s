#if canImport(Darwin)
import Darwin
#endif
import Foundation
import SpruceCore

/// Holds the Launch Services dump reader while `PerformanceStreamingShell` feeds it.
/// Only the runner's reading thread touches it until `run` returns.
final class PerformanceDumpCollector: @unchecked Sendable {
    var reader = PerformanceLaunchServicesDumpReader()
}

/// Runs a tool (no shell involved) and hands its standard output to `consume` in chunks
/// as it arrives, so a huge output such as `lsregister -dump` is never held in memory at
/// once. Stopping the calling task, or the timeout, terminates the tool (and kills it if it
/// is still running a moment later).
enum PerformanceStreamingShell {
    struct Result: Sendable {
        var status: Int32
        /// The start of standard error (at most `stderrLimit` bytes).
        var stderr: String
    }

    static let chunkSize = 1 << 20
    static let stderrLimit = 64 * 1024

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval,
                    consume: @escaping @Sendable (Data) -> Void) async -> Result {
        let control = PerformanceProcessControl()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    let out = Pipe()
                    let err = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    process.standardInput = FileHandle.nullDevice
                    do {
                        try control.start(process)
                    } catch {
                        continuation.resume(returning: Result(status: -1, stderr: error.localizedDescription))
                        return
                    }
                    let timer = DispatchWorkItem { control.stop() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                    // Drain stderr concurrently so a chatty tool cannot fill the pipe and stall.
                    let errors = PerformanceStderrCollector()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errors.drain(err.fileHandleForReading, limit: PerformanceStreamingShell.stderrLimit)
                        group.leave()
                    }
                    let handle = out.fileHandleForReading
                    while true {
                        let next: Data?
                        do {
                            next = try handle.read(upToCount: PerformanceStreamingShell.chunkSize)
                        } catch {
                            // Nobody reads the pipe any more: stop the tool so it can't block on it.
                            control.stop()
                            break
                        }
                        guard let chunk = next, !chunk.isEmpty else { break }
                        consume(chunk)
                    }
                    group.wait()
                    process.waitUntilExit()
                    control.markExited()
                    timer.cancel()
                    continuation.resume(returning: Result(status: process.terminationStatus,
                                                          stderr: String(decoding: errors.data, as: UTF8.self)))
                }
            }
        } onCancel: {
            control.stop()
        }
    }
}

/// Starts a process unless the run was already stopped, and stops it at most once: SIGTERM,
/// then SIGKILL if it's still running after a grace period (a child can inherit SIGTERM
/// blocked from the thread that launched it). Never signals a process that has exited.
private final class PerformanceProcessControl: @unchecked Sendable {
    static let killGrace: TimeInterval = 2

    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var exited = false

    func start(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if stopped { throw CancellationError() }
        try process.run()
        self.process = process
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        guard !exited, let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGrace) { self.forceKill() }
    }

    /// Called once `waitUntilExit()` has returned.
    func markExited() {
        lock.lock()
        defer { lock.unlock() }
        exited = true
    }

    private func forceKill() {
        lock.lock()
        defer { lock.unlock() }
        guard !exited, let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }
}

/// Keeps the start of a stream and discards the rest. Written by one thread, read by
/// another after a `DispatchGroup.wait()`.
private final class PerformanceStderrCollector: @unchecked Sendable {
    var data = Data()

    func drain(_ handle: FileHandle, limit: Int) {
        while true {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { return }
            if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
        }
    }
}
