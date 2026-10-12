import Foundation

// Foundation-only helpers for the Prism design system: deterministic noise, canvas
// mesh motion, particle maths, metric splitting and procedural sound synthesis.
// Kept free of SwiftUI/AppKit so the logic can be exercised anywhere.

// MARK: - Deterministic noise

enum PrismNoise {
    /// Stable pseudo-random value in 0..<1 for an index/salt pair (no shared state).
    static func unit(_ index: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(bitPattern: Int64(salt)) &* 0xC2B2_AE3D_27D4_EB4F
        x ^= x >> 33
        x = x &* 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        x = x &* 0xC4CE_B9FE_1A85_EC53
        x ^= x >> 33
        return Double(x >> 11) / Double(1 << 53)
    }

    /// Stable pseudo-random value in `range`.
    static func value(_ index: Int, _ salt: Int, in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit(index, salt)
    }
}

/// Small xorshift generator for bulk noise (grain texture, synthesis).
struct PrismXorShift {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x2545_F491_4F6C_DD1D : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform value in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// MARK: - Canvas motion (B.3.3)

enum PrismCanvasMath {
    /// One sine "wave" component: amplitude × sin(2π·t/period + phase).
    static func wave(_ t: Double, phase: Double, amplitude: Double, period: Double = 24) -> Double {
        sin(t / period * 2 * .pi + phase) * amplitude
    }

    /// The nine control points of the 3×3 mesh at time `t` (seconds). Corner and
    /// top-edge points stay fixed; the centre drifts ±0.08 on a 24 s sine, the left and
    /// right edge midpoints ±0.06 vertically (phases 0 and 3.4 rad) and the
    /// bottom-middle point ±0.10 horizontally on a 30 s sine.
    static func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func f(_ v: Double) -> Float { Float(v) }
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, f(0.5 + wave(t, phase: 0, amplitude: 0.06))),
            SIMD2<Float>(f(0.5 + wave(t, phase: 1.3, amplitude: 0.08)), f(0.55 + wave(t, phase: 2.1, amplitude: 0.07))),
            SIMD2<Float>(1, f(0.5 + wave(t, phase: 3.4, amplitude: 0.06))),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(f(0.5 + wave(t, phase: 4.2, amplitude: 0.10, period: 30)), 1),
            SIMD2<Float>(1, 1),
        ]
    }

    /// Centre (unit coordinates) of one of the three macOS 14 fallback blooms at `t`.
    /// Each bloom travels a slow Lissajous loop around its anchor.
    static func bloomCenter(_ index: Int, _ t: Double) -> (x: Double, y: Double) {
        switch index {
        case 0: // main pool behind the hero / orb
            return (0.5 + wave(t, phase: 0.4, amplitude: 0.07, period: 26),
                    0.88 + wave(t, phase: 1.9, amplitude: 0.05, period: 19))
        case 1: // left accent
            return (0.10 + wave(t, phase: 2.6, amplitude: 0.06, period: 34),
                    0.32 + wave(t, phase: 0.8, amplitude: 0.08, period: 23))
        default: // top-right accent2
            return (0.88 + wave(t, phase: 4.1, amplitude: 0.05, period: 15),
                    0.10 + wave(t, phase: 5.0, amplitude: 0.05, period: 21))
        }
    }

    /// Ambient intensity multiplier per screen state (B.3.3 `k`).
    enum Intensity {
        static let idle = 1.0
        static let scanning = 1.35
        static let results = 0.8
        static let celebrate = 1.6
        static let calm = 0.6
    }
}

// MARK: - Particles (B.13.5)

/// One particle of the inward-drifting scan dust.
struct PrismMote {
    var angle: Double
    var swirl: Double
    var startRadius: Double   // fraction of the field's half-size
    var endRadius: Double
    var size: Double
    var speed: Double
    var phase: Double
    var alpha: Double
    var usesSecondary: Bool

    static func seeded(_ i: Int) -> PrismMote {
        PrismMote(angle: PrismNoise.value(i, 1, in: 0...(2 * .pi)),
                  swirl: PrismNoise.value(i, 2, in: 0.4...1.2),
                  startRadius: PrismNoise.value(i, 3, in: 0.78...1.0),
                  endRadius: PrismNoise.value(i, 4, in: 0.30...0.42),
                  size: PrismNoise.value(i, 5, in: 1.5...3.5),
                  speed: PrismNoise.value(i, 6, in: 0.12...0.30),
                  phase: PrismNoise.unit(i, 7),
                  alpha: PrismNoise.value(i, 8, in: 0.35...0.8),
                  usesSecondary: PrismNoise.unit(i, 9) < 0.35)
    }

    /// Life fraction 0..<1 at time `t`.
    func life(at t: Double) -> Double {
        let v = (t * speed + phase).truncatingRemainder(dividingBy: 1)
        return v < 0 ? v + 1 : v
    }

    /// Position relative to the field centre (in fractions of the half-size), radius
    /// shrinking from start to end while swirling.
    func position(at t: Double) -> (x: Double, y: Double, opacity: Double, scale: Double) {
        let l = life(at: t)
        let r = startRadius + (endRadius - startRadius) * l
        let a = angle + l * swirl
        return (cos(a) * r, sin(a) * r, sin(l * .pi) * alpha, 1 - l * 0.6)
    }
}

/// One particle of the completion burst: flies outward with gravity and fades.
struct PrismBurstMote {
    var angle: Double
    var speed: Double     // points per second
    var size: Double
    var spin: Double
    var usesSecondary: Bool

    static func seeded(_ i: Int, count: Int) -> PrismBurstMote {
        let base = Double(i) / Double(max(count, 1)) * 2 * .pi
        return PrismBurstMote(angle: base + PrismNoise.value(i, 11, in: -0.18...0.18),
                              speed: PrismNoise.value(i, 12, in: 120...260),
                              size: PrismNoise.value(i, 13, in: 2.5...5.5),
                              spin: PrismNoise.value(i, 14, in: -3...3),
                              usesSecondary: i % 3 != 0)
    }

    /// Offset from the origin after `t` seconds, with gravity (y grows downward).
    func offset(at t: Double) -> (x: Double, y: Double) {
        let drag = 1 - min(t, 0.9) * 0.45
        return (cos(angle) * speed * t * drag, sin(angle) * speed * t * drag + 120 * t * t)
    }

    /// Opacity over the 0.9 s life.
    static func opacity(at t: Double, duration: Double = 0.9) -> Double {
        guard t >= 0, t < duration else { return 0 }
        let fadeIn = min(t / 0.08, 1)
        let fadeOut = 1 - pow(t / duration, 2)
        return fadeIn * fadeOut
    }
}

// MARK: - Metrics

enum PrismMetric {
    private static let units: Set<String> = ["bytes", "KB", "MB", "GB", "TB", "PB", "%"]

    /// Splits "6.2 GB" into ("6.2", "GB") so the unit can be set smaller. Strings that
    /// do not end in a known unit are returned whole with an empty unit.
    static func split(_ text: String) -> (value: String, unit: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.lastIndex(of: " ") else { return (trimmed, "") }
        let unit = String(trimmed[trimmed.index(after: space)...])
        let value = String(trimmed[..<space])
        guard units.contains(unit), !value.isEmpty, value.last?.isNumber == true else { return (trimmed, "") }
        return (value, unit)
    }

    /// Whole-percent text for accessibility values ("42 percent").
    static func percentText(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded())) percent"
    }
}

// MARK: - Sound synthesis (B.11, original procedural sounds)

/// Renders Spruce's short UI sounds procedurally (no sampled assets) as 16-bit mono
/// WAV data that `NSSound(data:)` can play.
enum PrismSynth {
    static let sampleRate = 44_100

    enum Voice: String, CaseIterable {
        case scanStart, scanComplete, cleanComplete, attention, error

        /// Nominal length in seconds (B.11 table).
        var duration: Double {
            switch self {
            case .scanStart: return 0.22
            case .scanComplete: return 0.48
            case .cleanComplete: return 0.9
            case .attention: return 0.3
            case .error: return 0.25
            }
        }
    }

    /// Float samples in -1...1, peak-normalised to -3 dBFS.
    static func samples(for voice: Voice) -> [Float] {
        let count = Int(Double(sampleRate) * voice.duration)
        var buffer = [Double](repeating: 0, count: count)
        switch voice {
        case .scanStart:
            // Soft, airy rising shimmer: three quick glassy grains, G6 → C7 → E7.
            for (i, f) in [1568.0, 2093.0, 2637.0].enumerated() {
                addBell(&buffer, frequency: f, start: Double(i) * 0.045, amplitude: 0.5 - Double(i) * 0.08, decay: 22)
            }
        case .scanComplete:
            // Two-note glassy chime rising a major third (E6 → G#6).
            addBell(&buffer, frequency: 1318.5, start: 0, amplitude: 0.8, decay: 7)
            addBell(&buffer, frequency: 1661.2, start: 0.14, amplitude: 0.9, decay: 6)
        case .cleanComplete:
            // Gentle filtered-noise whoosh, then a sparkle tail of tiny glass pings.
            addWhoosh(&buffer, start: 0, length: 0.42, amplitude: 0.55)
            let pings: [(Double, Double)] = [(3136, 0.34), (3951, 0.42), (3520, 0.50), (4699, 0.58), (4186, 0.68)]
            for (i, ping) in pings.enumerated() {
                addBell(&buffer, frequency: ping.0, start: ping.1, amplitude: 0.42 - Double(i) * 0.05, decay: 16)
            }
        case .attention:
            // Low rounded "bloop": a sine gliding down a fourth with a soft second harmonic.
            addGlide(&buffer, from: 523, to: 392, start: 0, length: 0.3, amplitude: 0.9, decay: 11, harmonic: 0.18)
        case .error:
            // Muted double tap.
            addGlide(&buffer, from: 210, to: 150, start: 0, length: 0.12, amplitude: 1, decay: 32, harmonic: 0.3)
            addGlide(&buffer, from: 210, to: 150, start: 0.11, length: 0.13, amplitude: 0.85, decay: 32, harmonic: 0.3)
        }
        return normalize(buffer, peak: 0.708)
    }

    /// RIFF/WAVE container (PCM, 16-bit, mono) for the given voice.
    static func wav(for voice: Voice) -> Data {
        wav(samples: samples(for: voice))
    }

    static func wav(samples: [Float]) -> Data {
        var data = Data()
        let dataBytes = UInt32(samples.count * 2)
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF")
        append32(36 + dataBytes)
        append("WAVE")
        append("fmt ")
        append32(16)                         // PCM chunk size
        append16(1)                          // PCM format
        append16(1)                          // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))     // byte rate
        append16(2)                          // block align
        append16(16)                         // bits per sample
        append("data")
        append32(dataBytes)
        data.reserveCapacity(data.count + samples.count * 2)
        for s in samples {
            let clamped = max(-1, min(1, s))
            append16(UInt16(bitPattern: Int16(clamped * Float(Int16.max))))
        }
        return data
    }

    // MARK: Voices

    /// Glass/bell-like tone: inharmonic partials (1, 2.756, 5.404) with fast decays.
    private static func addBell(_ buffer: inout [Double], frequency: Double, start: Double, amplitude: Double, decay: Double) {
        let partials: [(ratio: Double, amp: Double, decay: Double)] = [(1, 1, decay), (2.756, 0.32, decay * 1.7), (5.404, 0.11, decay * 2.6)]
        let first = Int(start * Double(sampleRate))
        guard first < buffer.count else { return }
        for n in first..<buffer.count {
            let t = Double(n - first) / Double(sampleRate)
            let attack = min(t / 0.004, 1)
            var v = 0.0
            for p in partials where frequency * p.ratio < Double(sampleRate) / 2 {
                v += p.amp * exp(-p.decay * t) * sin(2 * .pi * frequency * p.ratio * t)
            }
            buffer[n] += amplitude * attack * v
        }
    }

    /// Sine whose pitch glides exponentially between two frequencies.
    private static func addGlide(_ buffer: inout [Double], from f0: Double, to f1: Double, start: Double, length: Double,
                                 amplitude: Double, decay: Double, harmonic: Double) {
        let first = Int(start * Double(sampleRate))
        let last = min(buffer.count, first + Int(length * Double(sampleRate)))
        guard first < last else { return }
        var phase = 0.0
        for n in first..<last {
            let t = Double(n - first) / Double(sampleRate)
            let progress = t / length
            let f = f0 * pow(f1 / f0, progress)
            phase += 2 * .pi * f / Double(sampleRate)
            let attack = min(t / 0.006, 1)
            let release = min((length - t) / 0.02, 1)
            let env = attack * release * exp(-decay * t)
            buffer[n] += amplitude * env * (sin(phase) + harmonic * sin(2 * phase))
        }
    }

    /// Band-limited noise swell with a rising low-pass cutoff ("whoosh").
    private static func addWhoosh(_ buffer: inout [Double], start: Double, length: Double, amplitude: Double) {
        var rng = PrismXorShift(seed: 0x5EED_CAFE)
        let first = Int(start * Double(sampleRate))
        let last = min(buffer.count, first + Int(length * Double(sampleRate)))
        guard first < last else { return }
        var low = 0.0
        var band = 0.0
        for n in first..<last {
            let t = Double(n - first) / Double(sampleRate)
            let x = t / length
            let cutoff = 400 + 3200 * x                       // Hz, sweeping up
            let alpha = min(1, 2 * .pi * cutoff / Double(sampleRate))
            let white = rng.unit() * 2 - 1
            low += alpha * (white - low)
            band += alpha * (low - band)
            let env = sin(min(x, 1) * .pi) * (x < 0.7 ? 1 : max(0, 1 - (x - 0.7) / 0.3))
            buffer[n] += amplitude * env * (low - band * 0.5) * 2.2
        }
    }

    private static func normalize(_ buffer: [Double], peak: Double) -> [Float] {
        let maxValue = buffer.reduce(0) { max($0, abs($1)) }
        guard maxValue > 0 else { return buffer.map { Float($0) } }
        let gain = peak / maxValue
        // Short fade-out on the last 8 ms so no voice ends with a click.
        let fade = min(buffer.count, Int(0.008 * Double(sampleRate)))
        return buffer.enumerated().map { index, v in
            let remaining = buffer.count - index
            let tail = remaining < fade ? Double(remaining) / Double(fade) : 1
            return Float(v * gain * tail)
        }
    }
}
