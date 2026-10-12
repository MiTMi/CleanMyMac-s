import Foundation

/// Reads the CPU slices of a Mach-O executable (thin or universal) from its first bytes.
///
/// Only the header is parsed; the file is never modified (apps are never thinned).
public enum ApplicationsMachO {

    public enum CPU: Hashable, Sendable {
        case arm64
        case arm64e
        case x86_64
        case i386
        case ppc
        case ppc64
        case arm
        case other(Int32)
    }

    static let cpuTypeX86: Int32 = 7
    static let cpuTypeX86_64: Int32 = 0x0100_0007
    static let cpuTypeARM: Int32 = 12
    static let cpuTypeARM64: Int32 = 0x0100_000C
    static let cpuTypePowerPC: Int32 = 18
    static let cpuTypePowerPC64: Int32 = 0x0100_0012
    static let cpuSubtypeARM64E: Int32 = 2

    /// Number of bytes worth reading to classify a binary (fat headers with many slices fit easily).
    public static let headerLength = 4096

    /// CPU slices in a Mach-O header, or `[]` when the data is not a Mach-O binary.
    public static func cpus(fromHeader data: Data) -> [CPU] {
        let bytes = [UInt8](data.prefix(headerLength))
        guard bytes.count >= 8 else { return [] }
        let magicBE = readUInt32(bytes, 0, bigEndian: true)
        switch magicBE {
        case 0xCAFE_BABE, 0xCAFE_BABF:
            return fatSlices(bytes, is64: magicBE == 0xCAFE_BABF)
        case 0xFEED_FACE, 0xFEED_FACF:
            // Big-endian thin binary (PowerPC era).
            return [cpu(type: Int32(bitPattern: readUInt32(bytes, 4, bigEndian: true)),
                        subtype: Int32(bitPattern: readUInt32(bytes, 8, bigEndian: true)))]
        case 0xCEFA_EDFE, 0xCFFA_EDFE:
            // Little-endian thin binary (Intel, Apple silicon).
            guard bytes.count >= 12 else { return [] }
            return [cpu(type: Int32(bitPattern: readUInt32(bytes, 4, bigEndian: false)),
                        subtype: Int32(bitPattern: readUInt32(bytes, 8, bigEndian: false)))]
        default:
            return []
        }
    }

    /// Reads the header of the file at `path` (nil when unreadable).
    public static func cpus(atPath path: String) -> [CPU]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: headerLength)
        return cpus(fromHeader: data)
    }

    private static func fatSlices(_ bytes: [UInt8], is64: Bool) -> [CPU] {
        let count = Int(readUInt32(bytes, 4, bigEndian: true))
        // Java class files share the 0xCAFEBABE magic; their "count" is a large version number.
        guard count > 0, count < 32 else { return [] }
        let stride = is64 ? 32 : 20
        var result: [CPU] = []
        for index in 0..<count {
            let offset = 8 + index * stride
            guard offset + 8 <= bytes.count else { break }
            let type = Int32(bitPattern: readUInt32(bytes, offset, bigEndian: true))
            let subtype = Int32(bitPattern: readUInt32(bytes, offset + 4, bigEndian: true))
            result.append(cpu(type: type, subtype: subtype))
        }
        return result
    }

    static func cpu(type: Int32, subtype: Int32) -> CPU {
        if type == cpuTypeARM64 {
            return (subtype & 0x00FF_FFFF) == cpuSubtypeARM64E ? .arm64e : .arm64
        }
        if type == cpuTypeX86_64 { return .x86_64 }
        if type == cpuTypeX86 { return .i386 }
        if type == cpuTypePowerPC { return .ppc }
        if type == cpuTypePowerPC64 { return .ppc64 }
        if type == cpuTypeARM { return .arm }
        return .other(type)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int, bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        let b0 = UInt32(bytes[offset]), b1 = UInt32(bytes[offset + 1])
        let b2 = UInt32(bytes[offset + 2]), b3 = UInt32(bytes[offset + 3])
        return bigEndian ? (b0 << 24 | b1 << 16 | b2 << 8 | b3) : (b3 << 24 | b2 << 16 | b1 << 8 | b0)
    }
}
