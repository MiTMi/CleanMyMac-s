import Foundation

// App Permissions: read-only view of macOS privacy grants (TCC database), per service.
// Changes are limited to what macOS supports: `tccutil reset <Service> <bundle id>` (the
// app asks again next time) and opening the matching System Settings pane.

/// A macOS privacy service.
public struct ProtectionTCCService: Sendable, Hashable, Identifiable {
    /// TCC key ("kTCCServiceCamera"), or "location" for Location Services.
    public let id: String
    public let title: String
    /// Service name for `tccutil reset` (nil when it can't be reset from here).
    public let tccutilName: String?
    /// Anchor of System Settings › Privacy & Security ("Privacy_Camera").
    public let settingsAnchor: String?
    public let symbol: String
    public let detail: String
    /// Powerful permissions worth reviewing regularly.
    public let isSensitive: Bool

    public init(id: String, title: String, tccutilName: String?, settingsAnchor: String?, symbol: String,
                detail: String, isSensitive: Bool) {
        self.id = id
        self.title = title
        self.tccutilName = tccutilName
        self.settingsAnchor = settingsAnchor
        self.symbol = symbol
        self.detail = detail
        self.isSensitive = isSensitive
    }

    /// System Settings deep link for this service.
    public var settingsURLString: String {
        let base = "x-apple.systempreferences:com.apple.preference.security"
        guard let anchor = settingsAnchor else { return base + "?Privacy" }
        return base + "?" + anchor
    }
}

public enum ProtectionTCCCatalog {
    public static let locationServicesID = "location"

    public static let services: [ProtectionTCCService] = [
        s("kTCCServiceSystemPolicyAllFiles", "Full Disk Access", "SystemPolicyAllFiles", "Privacy_AllFiles", "internaldrive.fill",
          "Can read and change data in every folder, including Mail, Messages and other apps' data.", true),
        s("kTCCServiceAccessibility", "Accessibility", "Accessibility", "Privacy_Accessibility", "accessibility",
          "Can control your Mac: read what's on screen, click and type for you.", true),
        s("kTCCServiceScreenCapture", "Screen & System Audio Recording", "ScreenCapture", "Privacy_ScreenCapture",
          "rectangle.dashed.badge.record", "Can see everything on your screen and record system audio.", true),
        s("kTCCServiceListenEvent", "Input Monitoring", "ListenEvent", "Privacy_ListenEvent", "keyboard",
          "Can see every key you press and mouse move, even in other apps.", true),
        s("kTCCServicePostEvent", "Keyboard & Mouse Control", "PostEvent", "Privacy_Accessibility", "cursorarrow.click.2",
          "Can send keystrokes and clicks to other apps.", true),
        s("kTCCServiceCamera", "Camera", "Camera", "Privacy_Camera", "camera.fill",
          "Can turn on your camera.", true),
        s("kTCCServiceMicrophone", "Microphone", "Microphone", "Privacy_Microphone", "mic.fill",
          "Can listen through your microphone.", true),
        s("kTCCServiceSystemPolicyAppBundles", "App Management", "SystemPolicyAppBundles", "Privacy_AppBundles", "app.badge",
          "Can update or delete other apps.", false),
        s("kTCCServiceSystemPolicyAppData", "Other Apps' Data", "SystemPolicyAppData", nil, "square.stack.3d.down.right",
          "Can read data stored by other apps.", false),
        s("kTCCServiceAppleEvents", "Automation", "AppleEvents", "Privacy_Automation", "gearshape.2",
          "Can control other apps with AppleScript.", false),
        s("kTCCServiceSystemPolicyDesktopFolder", "Desktop Folder", "SystemPolicyDesktopFolder", "Privacy_FilesAndFolders",
          "menubar.dock.rectangle", "Can read and change files on your Desktop.", false),
        s("kTCCServiceSystemPolicyDocumentsFolder", "Documents Folder", "SystemPolicyDocumentsFolder", "Privacy_FilesAndFolders",
          "doc.fill", "Can read and change files in Documents.", false),
        s("kTCCServiceSystemPolicyDownloadsFolder", "Downloads Folder", "SystemPolicyDownloadsFolder", "Privacy_FilesAndFolders",
          "arrow.down.circle.fill", "Can read and change files in Downloads.", false),
        s("kTCCServiceSystemPolicyNetworkVolumes", "Network Volumes", "SystemPolicyNetworkVolumes", "Privacy_FilesAndFolders",
          "network", "Can read files on network drives.", false),
        s("kTCCServiceSystemPolicyRemovableVolumes", "Removable Volumes", "SystemPolicyRemovableVolumes", "Privacy_FilesAndFolders",
          "externaldrive.fill", "Can read files on USB drives and memory cards.", false),
        s("kTCCServiceAddressBook", "Contacts", "AddressBook", "Privacy_Contacts", "person.crop.circle.fill",
          "Can read your contacts.", false),
        s("kTCCServiceCalendar", "Calendars", "Calendar", "Privacy_Calendars", "calendar",
          "Can read and add calendar events.", false),
        s("kTCCServiceReminders", "Reminders", "Reminders", "Privacy_Reminders", "checklist",
          "Can read and add reminders.", false),
        s("kTCCServicePhotos", "Photos", "Photos", "Privacy_Photos", "photo.fill",
          "Can see your photo library.", false),
        s("kTCCServicePhotosAdd", "Photos (add only)", "PhotosAdd", "Privacy_Photos", "photo.badge.plus",
          "Can add photos to your library.", false),
        s("kTCCServiceBluetoothAlways", "Bluetooth", "BluetoothAlways", "Privacy_Bluetooth", "dot.radiowaves.left.and.right",
          "Can find and connect to Bluetooth devices.", false),
        s("kTCCServiceSpeechRecognition", "Speech Recognition", "SpeechRecognition", "Privacy_SpeechRecognition", "waveform",
          "Can send audio for speech recognition.", false),
        s("kTCCServiceMediaLibrary", "Media & Apple Music", "MediaLibrary", "Privacy_Media", "music.note",
          "Can access your music and media library.", false),
        s("kTCCServiceFocusStatus", "Focus", "FocusStatus", "Privacy_Focus", "moon.fill",
          "Can see whether you have Focus turned on.", false),
        s("kTCCServiceDeveloperTool", "Developer Tools", "DeveloperTool", "Privacy_DevTools", "hammer.fill",
          "Can run software that doesn't meet the system's security policy.", false),
        ProtectionTCCService(id: locationServicesID, title: "Location Services", tccutilName: nil,
                             settingsAnchor: "Privacy_LocationServices", symbol: "location.fill",
                             detail: "Apps that may use your location. macOS manages this list in System Settings.", isSensitive: false),
    ]

    private static func s(_ id: String, _ title: String, _ tcc: String?, _ anchor: String?, _ symbol: String,
                          _ detail: String, _ sensitive: Bool) -> ProtectionTCCService {
        ProtectionTCCService(id: id, title: title, tccutilName: tcc, settingsAnchor: anchor, symbol: symbol,
                             detail: detail, isSensitive: sensitive)
    }

    public static func service(_ id: String) -> ProtectionTCCService? { services.first { $0.id == id } }
}

/// Grant state stored in TCC's `auth_value`.
public enum ProtectionTCCAuth: Int, Codable, Sendable {
    case denied = 0
    case unknown = 1
    case allowed = 2
    case limited = 3

    public var label: String {
        switch self {
        case .denied: return "Not allowed"
        case .unknown: return "Not decided"
        case .allowed: return "Allowed"
        case .limited: return "Limited"
        }
    }

    public var isGranted: Bool { self == .allowed || self == .limited }
}

/// Which TCC database a grant came from.
public enum ProtectionTCCDatabase: String, Codable, Sendable {
    case user, system
}

/// One row of the TCC `access` table.
public struct ProtectionTCCGrant: Sendable, Hashable, Identifiable, Codable {
    public var service: String
    /// Bundle identifier (clientType 0) or executable path (clientType 1).
    public var client: String
    public var clientType: Int
    public var auth: ProtectionTCCAuth
    public var authReason: Int
    public var lastModified: Date?
    /// Target of Automation grants (the controlled app's bundle id).
    public var indirectObject: String?
    public var database: ProtectionTCCDatabase

    public init(service: String, client: String, clientType: Int, auth: ProtectionTCCAuth, authReason: Int,
                lastModified: Date?, indirectObject: String?, database: ProtectionTCCDatabase) {
        self.service = service
        self.client = client
        self.clientType = clientType
        self.auth = auth
        self.authReason = authReason
        self.lastModified = lastModified
        self.indirectObject = indirectObject
        self.database = database
    }

    public var id: String { "\(database.rawValue)|\(service)|\(client)|\(indirectObject ?? "")" }
    public var isBundleClient: Bool { clientType == 0 }
}

public enum ProtectionTCCParser {
    /// Query run with `sqlite3 -readonly -json`.
    public static let query = """
    SELECT service AS service, client AS client, client_type AS client_type, auth_value AS auth_value, \
    auth_reason AS auth_reason, last_modified AS last_modified, \
    IFNULL(indirect_object_identifier, '') AS indirect FROM access;
    """

    /// Parses `sqlite3 -json` output (an empty output means no rows).
    public static func parse(json: String, database: ProtectionTCCDatabase) -> [ProtectionTCCGrant] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let service = row["service"] as? String, let client = row["client"] as? String else { return nil }
            let authValue = int(row["auth_value"]) ?? 1
            let indirect = (row["indirect"] as? String).flatMap { $0.isEmpty || $0 == "UNUSED" ? nil : $0 }
            let modified = int(row["last_modified"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
            return ProtectionTCCGrant(service: service, client: client, clientType: int(row["client_type"]) ?? 0,
                                      auth: ProtectionTCCAuth(rawValue: authValue) ?? .unknown,
                                      authReason: int(row["auth_reason"]) ?? 0, lastModified: modified,
                                      indirectObject: indirect, database: database)
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as NSNumber: return v.intValue
        case let v as String: return Int(v)
        case let v as Double: return Int(v)
        default: return nil
        }
    }
}

/// Grants of one service, for the permissions list.
public struct ProtectionPermissionGroup: Sendable, Hashable, Identifiable {
    public var service: ProtectionTCCService
    public var grants: [ProtectionTCCGrant]

    public init(service: ProtectionTCCService, grants: [ProtectionTCCGrant]) {
        self.service = service
        self.grants = grants
    }

    public var id: String { service.id }
    public var grantedCount: Int { grants.filter { $0.auth.isGranted }.count }

    /// Groups grants by catalog service (unknown/internal services are dropped). Every
    /// catalog service is returned, even without grants, so the list mirrors System Settings.
    public static func groups(from grants: [ProtectionTCCGrant], includeEmpty: Bool = true) -> [ProtectionPermissionGroup] {
        var byService: [String: [ProtectionTCCGrant]] = [:]
        for grant in grants {
            byService[grant.service, default: []].append(grant)
        }
        return ProtectionTCCCatalog.services.compactMap { service in
            let list = (byService[service.id] ?? []).sorted { lhs, rhs in
                if lhs.auth.isGranted != rhs.auth.isGranted { return lhs.auth.isGranted }
                return lhs.client.localizedCaseInsensitiveCompare(rhs.client) == .orderedAscending
            }
            // De-duplicate the same client listed in both databases (keep the user DB row).
            var seen = Set<String>()
            let unique = list.filter { seen.insert("\($0.client)|\($0.indirectObject ?? "")").inserted }
            if unique.isEmpty && !includeEmpty { return nil }
            return ProtectionPermissionGroup(service: service, grants: unique)
        }
    }
}
