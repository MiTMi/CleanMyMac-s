import AppKit
import Foundation
import SpruceCore
import SpruceMac

/// Spruce's UI sounds (B.11). Every cue is synthesised procedurally at first use
/// (`PrismSynth`), so no audio assets ship and nothing resembles another product.
///
/// Playback rules:
/// * honours Settings › General › Play sounds (`SpruceSettings.playSounds`) and the
///   system "Play user interface sound effects" preference;
/// * never overlaps: a new cue stops the previous one;
/// * silent while the app is in the background unless `force` is set (e.g. a
///   user-initiated action from the menu bar monitor);
/// * volume 0.6.
@MainActor
enum SpruceSound {
    enum Cue: CaseIterable {
        /// Soft rising shimmer when the user starts a scan.
        case scanStart
        /// Two-note glassy chime when a scan finishes (skip for scans under ~1.5 s).
        case scanComplete
        /// Whoosh + sparkle tail when a clean/run completes.
        case cleanComplete
        /// Low rounded "bloop": threats found or action needed.
        case attention
        /// Muted double tap: something failed.
        case error

        fileprivate var voice: PrismSynth.Voice {
            switch self {
            case .scanStart: return .scanStart
            case .scanComplete: return .scanComplete
            case .cleanComplete: return .cleanComplete
            case .attention: return .attention
            case .error: return .error
            }
        }

        /// Built-in system sound used only if synthesis or decoding ever fails.
        fileprivate var fallbackName: String {
            switch self {
            case .scanStart: return "Tink"
            case .scanComplete: return "Glass"
            case .cleanComplete: return "Glass"
            case .attention: return "Pop"
            case .error: return "Basso"
            }
        }
    }

    private static var cache: [Cue: Data] = [:]
    private static var current: NSSound?

    /// Whether sounds may play right now (user setting + system UI sounds preference).
    static var isEnabled: Bool {
        SettingsStore.shared.settings.playSounds && systemUISoundsEnabled
    }

    /// The system "Play user interface sound effects" checkbox
    /// (`com.apple.sound.uiaudio.enabled`; missing means on).
    static var systemUISoundsEnabled: Bool {
        let key = "com.apple.sound.uiaudio.enabled"
        if let value = UserDefaults.standard.object(forKey: key) as? NSNumber {
            return value.boolValue
        }
        if let value = UserDefaults(suiteName: "com.apple.systemsound")?.object(forKey: key) as? NSNumber {
            return value.boolValue
        }
        return true
    }

    /// Plays `cue` if sounds are enabled and the app is frontmost (or `force`).
    static func play(_ cue: Cue, force: Bool = false) {
        guard isEnabled else { return }
        guard force || NSApplication.shared.isActive else { return }
        current?.stop()
        let sound = makeSound(cue)
        sound?.volume = 0.6
        current = sound
        sound?.play()
    }

    /// Renders all cues ahead of time so the first playback has no latency.
    static func preload() {
        for cue in Cue.allCases where cache[cue] == nil {
            cache[cue] = PrismSynth.wav(for: cue.voice)
        }
    }

    private static func makeSound(_ cue: Cue) -> NSSound? {
        let data: Data
        if let cached = cache[cue] {
            data = cached
        } else {
            data = PrismSynth.wav(for: cue.voice)
            cache[cue] = data
        }
        if let sound = NSSound(data: data) {
            return sound
        }
        return NSSound(named: NSSound.Name(cue.fallbackName))
    }
}
