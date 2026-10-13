import Foundation

/// Runs in-process AppleScript one script at a time.
///
/// `NSAppleScript` is not thread-safe: two scripts executing at once on different
/// threads (an administrator prompt from `PrivilegedRunner` while a System Events
/// query is waiting for its Automation consent, say) can crash the OSA runtime. Every
/// in-process script in the app goes through this single serial queue — use `run(_:)`,
/// or dispatch onto `queue` and call `executeNow(_:)` there.
public final class AppleScriptExecutor: @unchecked Sendable {
    public static let shared = AppleScriptExecutor()

    /// The one queue in-process AppleScript may run on.
    public let queue = DispatchQueue(label: "app.spruce.applescript", qos: .userInitiated)

    public enum Outcome: Sendable, Equatable {
        case success(String)
        /// `code` is the AppleScript error number (-128 = the user cancelled).
        case failure(code: Int, message: String)
    }

    public init() {}

    /// Compiles and runs `source` on `queue`, after any script already running.
    public func run(_ source: String) async -> Outcome {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.executeNow(source))
            }
        }
    }

    /// Compiles and runs `source` on the calling thread. Only call this on `queue`.
    public static func executeNow(_ source: String) -> Outcome {
        guard let script = NSAppleScript(source: source) else {
            return .failure(code: 0, message: "The script couldn't be prepared.")
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)."
            return .failure(code: code, message: message)
        }
        return .success(output.stringValue ?? "")
    }
}
