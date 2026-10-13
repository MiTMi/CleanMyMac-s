import Foundation

/// What a `checkup.scan` request (weekly reminder, Activity's "Run Checkup", the Dock
/// menu, `spruce://checkup?autostart=1`) does, given what the Checkup screen holds.
///
/// Spruce stays open for weeks (menu bar, launch at login), so the request must not just
/// show an old results or completion screen.
public enum CheckupScanRequest {
    /// Results older than this are stale (files may have changed since).
    public static let staleAfter: TimeInterval = 15 * 60

    /// The Checkup journey as far as a scan request is concerned.
    public enum Screen: Equatable, Sendable {
        case idle
        /// A scan or a run is in progress.
        case busy
        /// Results are on screen. `hasCustomChoices`: the user changed tiles or reviews.
        case results(finishedAt: Date?, hasCustomChoices: Bool)
        /// The completion screen of an earlier run.
        case done
    }

    public enum Response: Equatable, Sendable {
        /// Start a fresh scan now.
        case startScan
        /// Results are stale but hold the user's choices: ask before scanning again.
        case askToScanAgain
        /// Keep what's on screen (a scan or run in progress, or fresh results).
        case showCurrent
    }

    public static func response(to screen: Screen, now: Date = Date(),
                                staleAfter: TimeInterval = staleAfter) -> Response {
        switch screen {
        case .idle, .done:
            return .startScan
        case .busy:
            return .showCurrent
        case .results(let finishedAt, let hasCustomChoices):
            let isStale = finishedAt.map { now.timeIntervalSince($0) > staleAfter } ?? true
            guard isStale else { return .showCurrent }
            return hasCustomChoices ? .askToScanAgain : .startScan
        }
    }
}
