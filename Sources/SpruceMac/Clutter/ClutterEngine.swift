import Foundation
import SpruceCore

/// Large & old files, duplicates, similar images and downloads.
///
/// CONTRACT (used by AppModel and Checkup — keep these signatures):
/// * `public init()`
/// * `CheckupContributor` conformance (`checkupScan`, `checkupRun`)
/// * `GroupScanner` conformance (`scan`, `perform`) for the module's main review list
public final class ClutterEngine: CheckupContributor, GroupScanner {
    public let module: ModuleID = .clutter

    public init() {}

    // MARK: GroupScanner

    public func scan(progress: @escaping ProgressHandler) async throws -> [ScanGroup] {
        progress(ScanProgress(fraction: 1, message: "Not implemented yet"))
        return []
    }

    public func perform(_ items: [ScanItem], progress: @escaping ProgressHandler) async throws -> RunOutcome {
        RunOutcome(module: module, summary: "Not implemented yet")
    }

    // MARK: CheckupContributor

    public func checkupScan(progress: @escaping ProgressHandler) async throws -> CheckupTile {
        CheckupTile(module: module, headline: "—", detail: "Not implemented yet", status: .info)
    }

    public func checkupRun(progress: @escaping ProgressHandler) async throws -> RunOutcome {
        RunOutcome(module: module, summary: "Not implemented yet")
    }
}
