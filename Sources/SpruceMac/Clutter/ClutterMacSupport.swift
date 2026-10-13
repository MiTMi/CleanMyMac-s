import CoreGraphics
import CoreServices
import Darwin
import Foundation
import ImageIO
import SpruceCore

// MARK: - File metadata (Spotlight, extended attributes, stat flags)

/// Reads the per-file signals Clutter needs from Spotlight, extended attributes and
/// `lstat`. Every call is cheap, synchronous and safe from any thread.
enum ClutterFileMetadata {
    /// `SF_DATALESS` (sys/stat.h): the file's data lives in the cloud, not on this Mac.
    static let datalessFlag: UInt32 = 0x4000_0000

    /// True for cloud placeholders. Reading such a file would download it, so the
    /// Clutter walk never opens one.
    static func isPlaceholder(_ entry: FileEntry) -> Bool {
        guard entry.logicalSize > 0 else { return false }
        if entry.allocatedSize == 0 { return true }
        // Only partially allocated files can be dataless; skip the extra lstat otherwise.
        guard entry.allocatedSize < entry.logicalSize / 2 else { return false }
        var st = stat()
        guard lstat(entry.path, &st) == 0 else { return false }
        return st.st_flags & datalessFlag != 0
    }

    /// Creation (birth) time.
    static func creationDate(_ path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let t = st.st_birthtimespec
        guard t.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9)
    }

    /// Spotlight's last-opened date and date added. Files outside the Spotlight index
    /// (external volumes, excluded folders) fall back to the `com.apple.lastuseddate#PS`
    /// attribute Launch Services writes on the file itself.
    static func spotlightDates(_ path: String) -> (lastUsed: Date?, added: Date?) {
        var lastUsed: Date?
        var added: Date?
        if let item = MDItemCreate(kCFAllocatorDefault, path as CFString) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        }
        if lastUsed == nil { lastUsed = lastUsedAttribute(path) }
        return (lastUsed, added)
    }

    /// The 16-byte `timespec` in `com.apple.lastuseddate#PS`.
    static func lastUsedAttribute(_ path: String) -> Date? {
        guard let data = xattr(path, "com.apple.lastuseddate#PS"), data.count >= 16 else { return nil }
        let seconds = data.withUnsafeBytes { raw -> Int64 in
            var value: Int64 = 0
            withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: raw.prefix(8)) }
            return Int64(littleEndian: value)
        }
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Download provenance from extended attributes.
    static func downloadMetadata(_ path: String) -> ClutterDownloadMetadata {
        var meta = ClutterDownloadMetadata()
        if let data = xattr(path, "com.apple.quarantine") {
            meta.quarantine = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
        }
        if let data = xattr(path, "com.apple.metadata:kMDItemWhereFroms"),
           let urls = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
            meta.whereFroms = urls
        }
        if let data = xattr(path, "com.apple.metadata:kMDItemDownloadedDate"),
           let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            if let dates = value as? [Date] {
                meta.downloadedDate = dates.first
            } else if let date = value as? Date {
                meta.downloadedDate = date
            }
        }
        return meta
    }

    /// Reads an extended attribute without following symlinks.
    static func xattr(_ path: String, _ name: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0, size < 1 << 20 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { raw -> Int in
            getxattr(path, name, raw.baseAddress, size, 0, XATTR_NOFOLLOW)
        }
        guard read > 0 else { return nil }
        return data.prefix(read)
    }

    /// Adds creation date, last-opened date and date added.
    static func enriched(_ file: ClutterFile) -> ClutterFile {
        var copy = file
        if copy.created == nil { copy.created = creationDate(file.path) }
        if copy.lastOpened == nil || copy.dateAdded == nil {
            let dates = spotlightDates(file.path)
            if copy.lastOpened == nil { copy.lastOpened = dates.lastUsed }
            if copy.dateAdded == nil { copy.dateAdded = dates.added }
        }
        return copy
    }

    /// Lowercased names (without ".app") of apps in the Applications folders.
    static func installedAppNames() -> Set<String> {
        let folders = ["/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var names = Set<String>()
        for folder in folders {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for child in children where child.lowercased().hasSuffix(".app") {
                names.insert(((child as NSString).deletingPathExtension).lowercased())
            }
        }
        return names
    }
}

// MARK: - Image fingerprints

/// Builds perceptual fingerprints from 64-pixel ImageIO thumbnails (no full decode
/// when the file embeds a thumbnail). Never used inside Photos libraries.
enum ClutterThumbnailFingerprinter {
    /// Pictures smaller than this on their short side are icons or UI assets.
    static let minimumShortSide = 200

    static func fingerprint(path: String) -> ClutterImageFingerprint? {
        let url = URL(fileURLWithPath: path) as CFURL
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url, sourceOptions), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        // Animated GIFs and multi-page images are not photos.
        guard CGImageSourceGetCount(source) == 1 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard min(width, height) >= minimumShortSide else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
              let gray = grayscale(thumbnail) else { return nil }
        return ClutterImageFingerprint(path: path, thumbnail: gray, pixelWidth: width, pixelHeight: height)
    }

    /// Draws `image` into an 8-bit gray bitmap of the same size (at most 64 × 64),
    /// over white so transparent areas hash consistently.
    static func grayscale(_ image: CGImage) -> ClutterGrayImage? {
        let w = min(max(image.width, 1), 64)
        let h = min(max(image.height, 1), 64)
        var pixels = [UInt8](repeating: 255, count: w * h)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        return ClutterGrayImage(width: w, height: h, pixels: pixels)
    }
}

// MARK: - Background execution

/// Runs blocking file system work on a Dispatch queue so the Swift concurrency
/// cooperative pool is never blocked by disk I/O.
enum ClutterBackground {
    static func run<T>(qos: DispatchQoS.QoSClass = .utility, _ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(returning: work())
            }
        }
    }
}

/// Cancellation flag shared between a task's cancellation handler and blocking work.
final class ClutterCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Rate-limits progress callbacks (the UI throttles too, but crossing to the main
/// actor thousands of times per second is wasteful).
final class ClutterProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private let interval: TimeInterval

    init(interval: TimeInterval = 0.08) {
        self.interval = interval
    }

    func shouldEmit(force: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard force || now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}
