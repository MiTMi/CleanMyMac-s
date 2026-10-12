import SpruceCore
import SpruceMac
import SwiftUI

/// "Building the map…": animated lens, the folder being read, live counters (items,
/// folders, size) and the Stop orb with progress when the volume's usage is known.
struct SpaceMapScanningScreen: View {
    let screen: SpaceMapScreenModel

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geo in
            let lens = min(200, max(110, (geo.size.height - 420) / 1.4))
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.topInset)
                ZStack {
                    PrismScanDust(color: ModuleID.spaceMap.palette.accent2, secondary: Color.white)
                        .frame(width: lens * 2, height: lens * 2)
                    HeroLens(module: .spaceMap, size: lens, isAnimating: true, parallax: false)
                }
                .frame(height: lens * 1.4)
                status
                    .padding(.top, Spacing.m)
                counters
                    .padding(.top, Spacing.xl)
                Spacer(minLength: Spacing.l)
                ActionOrb(title: "Stop", subtitle: percentText, module: .spaceMap, progress: screen.stats.fraction,
                          isBusy: true) {
                    screen.cancelScan()
                }
                .padding(.bottom, Spacing.orbBottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .prismCanvasIntensity(PrismCanvasMath.Intensity.scanning)
    }

    private var title: String {
        if let target = screen.scanningTarget { return "Mapping \(target.title)…" }
        return "Building the map…"
    }

    private var percentText: String? {
        screen.stats.fraction.map { "\(Int(($0 * 100).rounded()))%" }
    }

    private var status: some View {
        let ink = PrismInk(contrast)
        return VStack(spacing: Spacing.s) {
            Text(title)
                .font(SpruceFont.flowHeadline)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
            PrismThrottledText(value: screen.stats.currentPath?.abbreviatingHome)
                .font(SpruceFont.mono)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.contentInset)
    }

    private var counters: some View {
        HStack(spacing: Spacing.xxl) {
            counter(value: ByteFormat.string(screen.stats.bytes), label: "Measured", accent: true)
            counter(value: CountFormat.grouped(screen.stats.files), label: "Files", accent: false)
            counter(value: CountFormat.grouped(screen.stats.folders), label: "Folders", accent: false)
            if screen.stats.elapsed >= 1 {
                counter(value: DurationFormat.short(screen.stats.elapsed), label: "Elapsed", accent: false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func counter(value: String, label: String, accent: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(SpruceFont.metricS)
                .foregroundStyle(accent ? ModuleID.spaceMap.palette.accentText : Ink.primary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: value)
            Text(label)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.tertiary)
        }
        .frame(minWidth: 90)
    }
}
