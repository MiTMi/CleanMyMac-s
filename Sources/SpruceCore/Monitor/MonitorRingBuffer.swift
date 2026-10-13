import Foundation

/// Sampling cadence and history sizes shared by the monitor engine and its UI.
public enum MonitorSampling {
    /// Seconds between live samples (CPU, memory, network, processes).
    public static let interval: TimeInterval = 2
    /// Samples kept for sparklines (60 × 2 s = the last two minutes).
    public static let historyLength = 60
    /// Startup-volume capacity is re-read this often (it is comparatively expensive).
    public static let diskInterval: TimeInterval = 10
    /// Battery / UPS state.
    public static let powerInterval: TimeInterval = 10
    /// Bluetooth peripheral batteries (IORegistry walk).
    public static let devicesInterval: TimeInterval = 30
    /// How often the Trash folders' modification dates are checked (a few `stat`s). The
    /// Trash is only walked again when one of them changed — see `MonitorTrashSchedule`.
    public static let trashCheckInterval: TimeInterval = 10
    /// A Trash that could not be listed (no Full Disk Access) is retried this often; the
    /// attempt fails at once, so it costs nothing until access is granted.
    public static let trashAccessRetry: TimeInterval = 60
    /// A forced refresh (menu opened) re-walks an unchanged Trash only when the last
    /// measurement is older than this.
    public static let trashForcedRefresh: TimeInterval = 600
    /// An unchanged Trash is re-walked at most this often anyway, to catch changes deep
    /// inside trashed folders (they don't touch the top-level folder's date).
    public static let trashMaximumAge: TimeInterval = 3600
    /// The startup disk's SMART status and temperature (`diskutil info`, two short processes).
    public static let diskHealthInterval: TimeInterval = 1800
    /// A forced refresh re-reads disk health when the last reading is older than this.
    public static let diskHealthForcedRefresh: TimeInterval = 120
    /// Mounted external drives (also refreshed on every mount and unmount).
    public static let volumesInterval: TimeInterval = 30
}

/// Fixed-capacity FIFO holding the most recent samples; the oldest is dropped first.
public struct MonitorRingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element]
    /// Index of the oldest element once the buffer is full (0 until then).
    private var start: Int

    public init(capacity: Int = MonitorSampling.historyLength) {
        self.capacity = max(1, capacity)
        self.storage = []
        self.start = 0
        storage.reserveCapacity(self.capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var isFull: Bool { storage.count == capacity }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[start] = element
            start = (start + 1) % capacity
        }
    }

    public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == Element {
        for element in elements { append(element) }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        start = 0
    }

    /// All samples, oldest first.
    public var elements: [Element] {
        guard start > 0 else { return storage }
        return Array(storage[start...]) + Array(storage[..<start])
    }

    /// The most recent sample.
    public var latest: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(start + storage.count - 1) % storage.count]
    }

    /// The last `n` samples, oldest first.
    public func suffix(_ n: Int) -> [Element] {
        Array(elements.suffix(max(0, n)))
    }
}

extension MonitorRingBuffer: Equatable where Element: Equatable {
    public static func == (lhs: MonitorRingBuffer, rhs: MonitorRingBuffer) -> Bool {
        lhs.capacity == rhs.capacity && lhs.elements == rhs.elements
    }
}

public extension MonitorRingBuffer where Element == Double {
    /// Largest sample, or 0 when empty.
    var maximum: Double { storage.max() ?? 0 }

    /// Arithmetic mean, or 0 when empty.
    var average: Double {
        storage.isEmpty ? 0 : storage.reduce(0, +) / Double(storage.count)
    }
}
