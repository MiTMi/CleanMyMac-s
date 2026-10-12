import CryptoKit
import Foundation
import Security
import SpruceCore

/// Code-signature checks (Security framework) and SHA-256 (CryptoKit) for the malware
/// scanner. Stateless, so one value can be shared across threads.
public struct ProtectionMacSystemProbe: ProtectionSystemProbe {
    public init() {}

    // MARK: Signing

    public func signing(of path: String) -> ProtectionSigningInfo {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        guard SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode) == errSecSuccess, let code = staticCode else {
            return .unknown
        }

        // Bundles: validate the executable and signature, not every resource (a full resource
        // check of a multi-gigabyte app would make scans crawl). Single files: full check.
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        var rawFlags = UInt32(truncatingIfNeeded: kSecCSCheckAllArchitectures)
        if isDirectory.boolValue {
            rawFlags |= UInt32(truncatingIfNeeded: kSecCSDoNotValidateResources)
        }
        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: rawFlags), nil)
        if validity == OSStatus(errSecCSUnsigned) {
            return ProtectionSigningInfo(status: .unsigned)
        }

        var infoRef: CFDictionary?
        let infoFlags = SecCSFlags(rawValue: UInt32(truncatingIfNeeded: kSecCSSigningInformation))
        let infoStatus = SecCodeCopySigningInformation(code, infoFlags, &infoRef)
        let info: [String: Any] = infoStatus == errSecSuccess ? ((infoRef as? [String: Any]) ?? [:]) : [:]
        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let certificates = (info[kSecCodeInfoCertificates as String] as? [SecCertificate]) ?? []
        let authority: String? = certificates.first.flatMap { certificate in
            SecCertificateCopySubjectSummary(certificate) as String?
        }

        guard validity == errSecSuccess else {
            return ProtectionSigningInfo(status: .invalid, teamID: teamID, identifier: identifier, authority: authority)
        }
        if certificates.isEmpty {
            // Ad-hoc or linker-signed: a signature without any developer identity.
            return ProtectionSigningInfo(status: .adHoc, teamID: nil, identifier: identifier, authority: nil)
        }
        if isAppleAnchored(code) {
            return ProtectionSigningInfo(status: .apple, teamID: teamID, identifier: identifier, authority: authority)
        }
        return ProtectionSigningInfo(status: .signed, teamID: teamID, identifier: identifier, authority: authority)
    }

    /// True for code signed by Apple itself ("anchor apple"), i.e. part of macOS or an
    /// Apple app. The signature was already validated, so only the requirement is checked.
    private func isAppleAnchored(_ code: SecStaticCode) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else { return false }
        let flags = SecCSFlags(rawValue: UInt32(truncatingIfNeeded: kSecCSBasicValidateOnly))
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    // MARK: Hashing

    public func sha256(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var failed = false
        while true {
            let chunk: Data = autoreleasepool {
                do {
                    return try handle.read(upToCount: 1 << 20) ?? Data()
                } catch {
                    failed = true
                    return Data()
                }
            }
            if failed { return nil }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
