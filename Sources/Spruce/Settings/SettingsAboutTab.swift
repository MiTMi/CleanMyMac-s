import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// About: version, system, safety principles and the independence notice.
struct SettingsAboutTab: View {
    var body: some View {
        ZStack {
            SettingsBackdrop(module: SettingsTab.about.module)
            ScrollView {
                VStack(spacing: Spacing.l) {
                    identity
                    principles
                    notice
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.xl)
            }
        }
    }

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: Spacing.s) {
            HeroLens(module: .checkup, size: 78, isAnimating: false, parallax: false)
                .frame(height: 104)
            Text("Spruce")
                .font(SpruceFont.display(30))
                .foregroundStyle(Ink.primary)
            Text(SettingsAboutInfo.versionLine)
                .font(SpruceFont.callout.monospacedDigit())
                .foregroundStyle(Ink.secondary)
                .textSelection(.enabled)
            Text("Clean, protect and speed up your Mac, with every change in your hands.")
                .font(SpruceFont.body)
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.s) {
                PrismChip(text: SettingsAboutInfo.systemLine, color: ModuleID.spaceMap.palette.accent, symbol: "desktopcomputer")
                PrismChip(text: SettingsAboutInfo.architectureLine, color: ModuleID.spaceMap.palette.accent2, symbol: "cpu")
            }
            .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Principles

    private var principles: some View {
        GlassCard(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Safety principles", symbol: "checkmark.shield")
                ForEach(SettingsAboutInfo.principles, id: \.title) { principle in
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Image(systemName: principle.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ModuleID.spaceMap.palette.accentText)
                            .frame(width: 20)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(principle.title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                            Text(principle.detail)
                                .font(SpruceFont.caption)
                                .foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: Notice

    private var notice: some View {
        VStack(spacing: Spacing.xs) {
            Text("Spruce is an independent app. It is not affiliated with, endorsed by or sponsored by MacPaw or any other developer of Mac utilities.")
            Text("All artwork, sounds and text in Spruce are original. Built with SwiftUI; no third-party code.")
        }
        .font(SpruceFont.caption)
        .foregroundStyle(Ink.tertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Static facts shown on the About tab.
enum SettingsAboutInfo {
    struct Principle: Sendable {
        var symbol: String
        var title: String
        var detail: String
    }

    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?) where build != short: return "Version \(short) (\(build))"
        case let (short?, _): return "Version \(short)"
        default: return "Development build"
        }
    }

    static var systemLine: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let patch = v.patchVersion > 0 ? ".\(v.patchVersion)" : ""
        return "macOS \(v.majorVersion).\(v.minorVersion)\(patch)"
    }

    static var architectureLine: String {
        #if arch(arm64)
        return "Apple silicon"
        #else
        return "Intel"
        #endif
    }

    static let principles: [Principle] = [
        Principle(symbol: "eye", title: "You review before anything happens",
                  detail: "Scans only look. Nothing is removed, disabled or changed until you choose it and confirm."),
        Principle(symbol: "trash", title: "Trash first",
                  detail: "Files go to the Trash so you can put them back. Only caches, logs and temporary files that rebuild themselves are deleted directly."),
        Principle(symbol: "checkmark.seal", title: "Only safe items are pre-selected",
                  detail: "Anything that deserves a closer look starts unchecked; risky items always ask again."),
        Principle(symbol: "app.badge.checkmark", title: "Apps stay intact",
                  detail: "Spruce never strips languages or architectures from app bundles, so code signatures stay valid."),
        Principle(symbol: "lock.shield", title: "Protected locations stay protected",
                  detail: "Every removal is re-checked against a list of system and personal locations Spruce refuses to touch, and your ignore list."),
        Principle(symbol: "key", title: "Administrator rights only when needed",
                  detail: "A handful of fixed system tasks ask for your password each time. No helper stays installed."),
        Principle(symbol: "list.bullet.rectangle", title: "Everything is logged",
                  detail: "Each file moved or removed is written to the operations log, and every run to your activity history."),
    ]
}
