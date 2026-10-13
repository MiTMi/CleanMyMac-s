import AppKit
import Darwin
import Foundation
import SpruceCore

/// One reading of the heavy-consumers list.
public struct PerformanceConsumerSnapshot: Sendable {
    public var consumers: [PerformanceConsumer]
    public var memory: PerformanceMemoryReading?
    public var date: Date

    public init(consumers: [PerformanceConsumer], memory: PerformanceMemoryReading?, date: Date = Date()) {
        self.consumers = consumers
        self.memory = memory
        self.date = date
    }
}

extension PerformanceEngine {
    /// Samples running processes with `ps` and groups helpers under their app.
    public func sampleConsumers(sort: PerformanceConsumerSort, limit: Int = 25) async -> PerformanceConsumerSnapshot {
        let result = await Shell.run("/bin/ps", PerformanceProcessParser.psArguments, timeout: 10)
        let samples = PerformanceProcessParser.parse(result.stdout)
        let consumers = PerformanceConsumerAggregator.aggregate(samples, userUID: getuid(), ownPID: getpid(), sort: sort, limit: limit)
        return PerformanceConsumerSnapshot(consumers: consumers, memory: PerformanceSystemProbe.memory())
    }

    /// Quits a consumer. Apps get a normal quit (they can ask to save) or a force quit;
    /// other processes you own get SIGTERM or SIGKILL. Returns true once it has exited.
    public func quit(_ consumer: PerformanceConsumer, force: Bool) async -> Bool {
        guard consumer.canQuit, consumer.ownedByUser else { return false }
        if let appPath = consumer.appPath {
            let target = URL(fileURLWithPath: appPath).standardizedFileURL.path
            let running = NSWorkspace.shared.runningApplications.filter {
                $0.bundleURL?.standardizedFileURL.path == target && !$0.isTerminated
            }
            if !running.isEmpty {
                for app in running {
                    if force { _ = app.forceTerminate() } else { _ = app.terminate() }
                }
                let pids = running.map(\.processIdentifier)
                return await waitForExit(pids, timeout: force ? 4 : 10)
            }
        }
        // Not a registered app (a background process or helper bundle): signal what we own.
        let signal = force ? SIGKILL : SIGTERM
        let mine = consumer.pids.filter { $0 > 1 && $0 != getpid() }
        for pid in mine { _ = kill(pid, signal) }
        return await waitForExit(mine, timeout: force ? 3 : 6)
    }

    private func waitForExit(_ pids: [Int32], timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pids.allSatisfy({ !Self.isAlive($0) }) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return pids.allSatisfy { !Self.isAlive($0) }
    }

    static func isAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM   // exists but belongs to someone else
    }
}
