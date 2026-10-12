import SpruceCore
import SpruceMac
import SwiftUI

/// Scanning: all included areas run at once. Each area shows its live status in the
/// checklist; the ring combines their progress and the total found so far grows.
@MainActor
struct CheckupScanningScreen: View {
    let session: CheckupSession

    var body: some View {
        ScanningView(module: .checkup, progress: session.scanProgress, title: "Checking your Mac…",
                     stopTitle: "Stop", onStop: { session.stopScan() },
                     steps: session.board.areas.map(CheckupStepMapping.scanStep), showsBytes: true)
            .task {
                // Keeps the combined ring moving for areas that report no fraction.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { break }
                    await session.tick()
                }
            }
    }
}

/// Running: the selected areas, one after another, with overall progress. Stop lets
/// the current area finish and skips the rest.
@MainActor
struct CheckupRunningScreen: View {
    let session: CheckupSession

    var body: some View {
        if let board = session.runBoard {
            ScanningView(module: .checkup, progress: progress(board),
                         title: session.stopRequested ? "Finishing up…" : "Working on it…",
                         stopTitle: session.stopRequested ? "Stopping" : "Stop",
                         onStop: { session.requestStop() },
                         steps: board.steps.map(CheckupStepMapping.runStep), showsBytes: false)
        } else {
            ScanningView(module: .checkup, progress: ScanProgress(fraction: nil, message: "Preparing…"),
                         title: "Working on it…", showsBytes: false)
        }
    }

    private func progress(_ board: CheckupRunBoard) -> ScanProgress {
        var parts: [String] = []
        if board.freedBytes > 0 {
            parts.append("Freed \(ByteFormat.string(board.freedBytes)) so far")
        }
        if session.stopRequested {
            parts.append("Stopping after the current area")
        } else if let current = board.current {
            let message = current.progress.message
            parts.append(message.isEmpty ? "\(current.module.title)…" : "\(current.module.title) · \(message)")
        }
        return ScanProgress(fraction: board.overallFraction, message: parts.joined(separator: " — "),
                            current: board.current?.progress.current, bytesFound: board.freedBytes)
    }
}

/// Maps Checkup area/run states onto the design system's checklist rows.
enum CheckupStepMapping {
    static func scanStep(_ area: CheckupArea) -> PrismScanStep {
        let state: PrismScanStep.State
        switch area.state {
        case .waiting: state = .waiting
        case .scanning: state = .running
        case .finished(let tile): state = .done(CheckupCopy.stepResult(tile))
        case .excluded: state = .skipped("Off in Settings")
        case .unsupported: state = .skipped("Unavailable")
        case .failed: state = .failed("Couldn't finish")
        }
        return PrismScanStep(id: area.module.rawValue, title: area.module.title, symbol: area.module.palette.symbol,
                             state: state, module: area.module)
    }

    static func runStep(_ step: CheckupRunStep) -> PrismScanStep {
        let state: PrismScanStep.State
        switch step.state {
        case .waiting: state = .waiting
        case .running: state = .running
        case .done(let outcome):
            if !outcome.failures.isEmpty && outcome.processedCount == 0 && outcome.freedBytes == 0 {
                state = .failed("Couldn't complete")
            } else {
                state = .done(shortResult(outcome))
            }
        case .failed: state = .failed("Couldn't finish")
        case .skipped: state = .skipped("Not run")
        }
        return PrismScanStep(id: step.module.rawValue, title: step.module.title, symbol: step.module.palette.symbol,
                             state: state, module: step.module, runningLabel: "Working…")
    }

    /// "2.4 GB", "12 items", "Done", with a marker when some items failed.
    static func shortResult(_ outcome: RunOutcome) -> String {
        let base: String
        if outcome.freedBytes > 0 {
            base = ByteFormat.string(outcome.freedBytes)
        } else if outcome.processedCount > 0 {
            base = CountFormat.items(outcome.processedCount)
        } else {
            base = "Done"
        }
        return outcome.failures.isEmpty ? base : "\(base) · \(CountFormat.grouped(outcome.failures.count)) skipped"
    }
}
