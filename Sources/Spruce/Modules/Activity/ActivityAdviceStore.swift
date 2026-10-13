import Foundation
import Observation
import SpruceCore

/// The user's choices about Mac Health suggestions: snoozed and turned-off cards, and the
/// "Show suggestions" switch. Saved in `Application Support/Spruce/advisor.json`.
///
/// Hiding a card never changes the score (see `ActivityAdviceState`). The Activity screen
/// applies these choices to `AppModel.healthReport` with `ActivityHealthReport.applying(_:now:)`.
/// Settings can bind `showSuggestions` and call `restoreAll()` ("Reset hidden suggestions").
@MainActor
@Observable
final class ActivityAdviceStore {
    static let shared = ActivityAdviceStore()

    nonisolated static var defaultURL: URL { SprucePaths.applicationSupport.appendingPathComponent("advisor.json") }

    private(set) var state: ActivityAdviceState

    private let store: JSONFileStore<ActivityAdviceState>

    init(url: URL = ActivityAdviceStore.defaultURL) {
        store = JSONFileStore(url: url)
        state = (store.load() ?? ActivityAdviceState()).pruned(now: Date())
    }

    /// "Show suggestions". When off, only critical problems and threats are listed.
    var showSuggestions: Bool {
        get { state.showSuggestions }
        set { update { $0.showSuggestions = newValue } }
    }

    /// Snoozed or turned-off cards that still apply.
    func holdCount(now: Date = Date()) -> Int {
        state.activeHolds(now: now).count
    }

    /// The hold that hides `recommendation` right now, if any.
    func hold(for recommendation: ActivityRecommendation, now: Date = Date()) -> ActivityAdviceHold? {
        state.hold(for: recommendation, now: now)
    }

    /// "Snooze for …". No effect on threats.
    func snooze(_ recommendation: ActivityRecommendation, now: Date = Date()) {
        update { $0.snooze(recommendation, now: now) }
    }

    /// "Don't Suggest This Again". No effect on threats or critical problems.
    func dismiss(_ recommendation: ActivityRecommendation, now: Date = Date()) {
        update { $0.dismiss(recommendation, now: now) }
    }

    /// "Show Again" for one hidden card.
    func restore(_ recommendation: ActivityRecommendation) {
        update { $0.restore(recommendation) }
    }

    /// "Reset Hidden Suggestions": every snoozed or turned-off card shows again.
    func restoreAll() {
        update { $0.restoreAll() }
    }

    private func update(_ change: (inout ActivityAdviceState) -> Void) {
        var next = state
        change(&next)
        next = next.pruned(now: Date())
        guard next != state else { return }
        state = next
        try? store.save(next)
    }
}
