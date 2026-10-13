import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// The five onboarding pages. Each fits the ~640 × 390 pt area between the top bar and
// the progress/buttons bar of `OnboardingView`.

// MARK: - Welcome

struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            HeroLens(module: .checkup, size: 104, isAnimating: true)
                .frame(height: 146)
            VStack(spacing: Spacing.xs) {
                Text("Welcome to Spruce")
                    .font(SpruceFont.display(32))
                    .foregroundStyle(Ink.primary)
                Text("A calm, careful way to keep your Mac clean, protected and fast.")
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: Spacing.m) {
                OnboardingFeatureCard(module: .cleanup, symbol: "trash.circle", title: "Clean",
                                      detail: "Clear caches, logs, leftovers and clutter.")
                OnboardingFeatureCard(module: .protection, symbol: "shield.lefthalf.filled", title: "Protect",
                                      detail: "Find malware and privacy traces, watch startup items.")
                OnboardingFeatureCard(module: .performance, symbol: "gauge.with.dots.needle.67percent", title: "Speed up",
                                      detail: "Tame login items, run maintenance, free memory.")
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xxl2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingFeatureCard: View {
    var module: ModuleID
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PrismCategoryBadge(symbol: symbol, module: module, size: 28)
            Text(title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
            Text(detail)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(Spacing.m)
        .prismSurface(radius: Radius.row)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Safety promise

struct OnboardingSafetyPage: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            HeroLens(module: .protection, size: 54, glyph: "hand.raised.fill", parallax: false)
                .frame(height: 76)
            Text("Your Mac, your call")
                .font(SpruceFont.flowHeadline)
                .foregroundStyle(Ink.primary)
            VStack(alignment: .leading, spacing: Spacing.s + 2) {
                OnboardingPromiseRow(symbol: "eye", title: "You review everything first",
                                     detail: "Scans only look. Nothing is removed until you choose it and confirm.")
                OnboardingPromiseRow(symbol: "trash", title: "Trash, not gone",
                                     detail: "Files move to the Trash so you can put them back. Only caches and logs that rebuild themselves are deleted directly.")
                OnboardingPromiseRow(symbol: "checkmark.seal", title: "Only safe items are pre-selected",
                                     detail: "Anything that deserves a closer look starts unchecked, and apps themselves are never modified.")
                OnboardingPromiseRow(symbol: "lock.shield", title: "Private by design",
                                     detail: "No account and no analytics. Nothing about your Mac leaves it.")
            }
            .padding(Spacing.l)
            .prismSurface(radius: Radius.container)
        }
        .padding(.horizontal, Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingPromiseRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ModuleID.protection.palette.accentText)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                Text(detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Full Disk Access

struct OnboardingAccessPage: View {
    @Environment(AppModel.self) private var model
    var flow: OnboardingFlow
    var onGranted: () -> Void

    var body: some View {
        let granted = model.hasFullDiskAccess
        VStack(spacing: Spacing.m) {
            HeroLens(module: .applications, size: 60, mood: granted ? .clean : .standard,
                     glyph: granted ? "lock.open.fill" : "lock.fill", parallax: false)
                .frame(height: 84)
            VStack(spacing: Spacing.xs) {
                Text("Allow Full Disk Access")
                    .font(SpruceFont.flowHeadline)
                    .foregroundStyle(Ink.primary)
                Text("macOS keeps some folders private: Mail downloads, Safari and Messages caches, other apps' containers. With access, Spruce can find junk and threats there too. It only reads while scanning.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if granted {
                grantedCard
            } else {
                stepsCard
            }
            statusRow(granted: granted)
        }
        .padding(.horizontal, Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // There is no callback for Full Disk Access: re-check every 1.5 s while visible.
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        .onChange(of: model.hasFullDiskAccess) { _, nowGranted in
            if nowGranted && flow.openedPrivacySettings { onGranted() }
        }
        .animation(Motion.standard, value: granted)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s + 2) {
            SettingsStepRow(number: 1, text: "Click Open System Settings. Privacy & Security › Full Disk Access opens.",
                            module: .applications)
            SettingsStepRow(number: 2, text: "Turn on Spruce. If it isn't listed, click + and choose Spruce, or drag it in from Finder.",
                            module: .applications)
            SettingsStepRow(number: 3, text: "Come back here. Spruce notices by itself; reopening when macOS asks is fine.",
                            module: .applications)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismSurface(radius: Radius.container)
    }

    private var grantedCard: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(StatusColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access is on").font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                Text("Checkup, Cleanup and Protection can see every location they need.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.l)
        .prismSurface(radius: Radius.container, tint: StatusColor.success)
        .transition(.opacity)
    }

    private func statusRow(granted: Bool) -> some View {
        HStack(spacing: Spacing.s) {
            if granted {
                StatusPill(text: "Access granted", status: .clear, symbol: "checkmark")
            } else {
                ProgressView().controlSize(.small)
                Text(flow.openedPrivacySettings ? "Waiting for access…" : "Not granted yet")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
                Spacer().frame(width: Spacing.m)
                PrismTextButton(title: "Show Spruce in Finder", symbol: "arrow.up.forward", module: .applications) {
                    SettingsFinder.revealSpruce()
                }
            }
        }
    }
}

// MARK: - Alerts, menu bar, login

struct OnboardingStayInformedPage: View {
    @Environment(AppModel.self) private var model
    var flow: OnboardingFlow

    var body: some View {
        @Bindable var store = model.settings
        VStack(spacing: Spacing.m) {
            HeroLens(module: .performance, size: 60, glyph: "bell.badge.fill", parallax: false)
                .frame(height: 84)
            VStack(spacing: Spacing.xs) {
                Text("Stay in the loop")
                    .font(SpruceFont.flowHeadline)
                    .foregroundStyle(Ink.primary)
                Text("Choose how Spruce keeps an eye on your Mac. You can change these anytime in Settings.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 0) {
                OnboardingOptionRow(symbol: "bell.fill", module: .performance, title: "Alerts & reminders",
                                    detail: "Low disk space, heavy memory use, threats and a nudge when a Checkup is due.") {
                    notificationTrailing
                }
                Divider().opacity(0.5).padding(.leading, 56)
                OnboardingOptionRow(symbol: "menubar.rectangle", module: .performance, title: "Menu bar monitor",
                                    detail: "CPU, memory, storage and network at a glance.") {
                    Toggle("Menu bar monitor", isOn: $store.settings.showMenuBarMonitor)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Divider().opacity(0.5).padding(.leading, 56)
                OnboardingOptionRow(symbol: "power", module: .performance, title: "Open at login",
                                    detail: "Keeps alerts and real-time protection running after a restart.") {
                    Toggle("Open at login", isOn: loginBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            .padding(.vertical, Spacing.xs)
            .prismSurface(radius: Radius.container)
            .tint(ModuleID.performance.palette.accent)
            footnote
        }
        .padding(.horizontal, Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var notificationTrailing: some View {
        switch flow.notificationStatus {
        case .allowed:
            StatusPill(text: "On", status: .clear, symbol: "checkmark")
        case .denied:
            Button("Open Settings") { SettingsNotificationAccess.openSystemSettings() }
                .buttonStyle(PrismCapsuleButtonStyle(role: .secondary))
        case .notDetermined:
            StatusPill(text: "Not set up", status: .attention)
        case .unavailable:
            StatusPill(text: "Unavailable", status: .unavailable)
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if let error = flow.loginError {
            SettingsNote(text: error, symbol: "xmark.octagon.fill", color: StatusColor.danger)
        } else if flow.loginState == .needsApproval {
            SettingsNote(text: "macOS needs your approval in System Settings › General › Login Items.")
        } else if flow.loginState == .on {
            SettingsNote(text: "macOS may show a “Background Items Added” notice. That's Spruce's login item.",
                         symbol: "info.circle.fill", color: StatusColor.info)
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { flow.loginState.isRequested },
            set: { enabled in
                flow.loginError = SettingsLoginItem.set(enabled, store: model.settings)
                flow.loginState = SettingsLoginItem.state
            }
        )
    }
}

private struct OnboardingOptionRow<Trailing: View>: View {
    var symbol: String
    var module: ModuleID
    var title: String
    var detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.m) {
            PrismCategoryBadge(symbol: symbol, module: module, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                Text(detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            trailing
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s + 2)
    }
}

// MARK: - Ready

struct OnboardingReadyPage: View {
    @Environment(AppModel.self) private var model
    var flow: OnboardingFlow

    var body: some View {
        VStack(spacing: Spacing.m) {
            HeroLens(module: .checkup, size: 96, isAnimating: true, mood: .clean)
                .frame(height: 134)
            VStack(spacing: Spacing.xs) {
                Text("You're all set")
                    .font(SpruceFont.display(30))
                    .foregroundStyle(Ink.primary)
                Text("Start with a Checkup: one scan for junk, threats, speed, updates and clutter. Nothing is removed until you review it.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            summary
            if !model.hasFullDiskAccess {
                Text("You can grant Full Disk Access later in Settings › Privacy.")
                    .font(SpruceFont.caption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.horizontal, Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: some View {
        let settings = model.settings.settings
        return HStack(spacing: Spacing.s) {
            if model.hasFullDiskAccess {
                PrismChip(text: "Full Disk Access", color: StatusColor.success, symbol: "checkmark")
            } else {
                PrismChip(text: "Limited disk access", color: StatusColor.warning, symbol: "exclamationmark")
            }
            if flow.notificationStatus == .allowed {
                PrismChip(text: "Alerts on", color: StatusColor.success, symbol: "checkmark")
            } else {
                PrismChip(text: "Alerts off", color: StatusColor.info, symbol: "bell.slash")
            }
            PrismChip(text: settings.showMenuBarMonitor ? "Menu bar monitor" : "Menu bar hidden",
                      color: settings.showMenuBarMonitor ? StatusColor.success : StatusColor.info,
                      symbol: settings.showMenuBarMonitor ? "checkmark" : "eye.slash")
            if flow.loginState.isRequested {
                PrismChip(text: "Opens at login", color: StatusColor.success, symbol: "checkmark")
            }
        }
    }
}
