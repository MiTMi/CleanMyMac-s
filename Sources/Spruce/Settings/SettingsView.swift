import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Settings window. CONTRACT: keep `SettingsView`.
///
/// A standard macOS toolbar-tab Settings window. Every control binds straight to
/// `model.settings` (`SettingsStore`), which persists each change immediately.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabContent(tab: tab, store: model.settings)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
        .preferredColorScheme(.dark)
        // Keep the scheduled Checkup reminders in step with the settings that shape them
        // (interval and time changes resync from Settings › Notifications).
        .onAppear { SettingsReminderScheduler.sync(model.settings.settings) }
        .onChange(of: model.settings.settings.weeklyCleanupReminder) { _, _ in
            SettingsReminderScheduler.sync(model.settings.settings)
        }
        .onChange(of: model.settings.settings.playSounds) { _, _ in
            SettingsReminderScheduler.sync(model.settings.settings)
        }
    }
}

// MARK: - Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case scanning
    case ignoreList
    case protection
    case notifications
    case privacy
    case advanced
    case about

    /// `UserDefaults.standard` key remembering the last tab (a per-window convenience).
    static let storageKey = "settings.selectedTab"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .scanning: return "Scanning"
        case .ignoreList: return "Ignore List"
        case .protection: return "Protection"
        case .notifications: return "Notifications"
        case .privacy: return "Privacy"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    /// Longer title shown in the tab's header.
    var headerTitle: String {
        switch self {
        case .privacy: return "Privacy & Permissions"
        case .about: return "About Spruce"
        default: return title
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Startup, menu bar, sounds and motion."
        case .scanning: return "What Checkup, Cleanup and Clutter look at."
        case .ignoreList: return "Files, folders and apps Spruce never touches."
        case .protection: return "Real-time protection, scan depth and detection sources."
        case .notifications: return "Which alerts and reminders Spruce may show."
        case .privacy: return "Access Spruce needs, and why. Your files never leave your Mac."
        case .advanced: return "Logs, app data, history and resets."
        case .about: return "Version, safety principles and credits."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .scanning: return "scope"
        case .ignoreList: return "eye.slash"
        case .protection: return "shield.lefthalf.filled"
        case .notifications: return "bell.badge"
        case .privacy: return "hand.raised"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    /// Palette used for the tab's badge, canvas tint and control accents.
    var module: ModuleID {
        switch self {
        case .general: return .checkup
        case .scanning: return .cleanup
        case .ignoreList: return .clutter
        case .protection: return .protection
        case .notifications: return .performance
        case .privacy: return .applications
        case .advanced: return .toolbox
        case .about: return .spaceMap
        }
    }
}

enum SettingsLayout {
    static let width: CGFloat = 700
    static let height: CGFloat = 580
}

/// Routes a tab to its view.
private struct SettingsTabContent: View {
    var tab: SettingsTab
    var store: SettingsStore

    var body: some View {
        switch tab {
        case .general: SettingsGeneralTab(store: store)
        case .scanning: SettingsScanningTab(store: store)
        case .ignoreList: SettingsIgnoreListTab(store: store)
        case .protection: SettingsProtectionTab(store: store)
        case .notifications: SettingsNotificationsTab(store: store)
        case .privacy: SettingsPrivacyTab(store: store)
        case .advanced: SettingsAdvancedTab(store: store)
        case .about: SettingsAboutTab()
        }
    }
}

// MARK: - Page chrome

/// Header + grouped form on a calm, module-tinted Prism canvas.
struct SettingsPage<Content: View>: View {
    var tab: SettingsTab
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabHeader(tab: tab)
                .padding(.horizontal, Spacing.xl + Spacing.xs)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxs)
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background { SettingsBackdrop(module: tab.module) }
        .tint(tab.module.palette.accent)
    }
}

struct SettingsTabHeader: View {
    var tab: SettingsTab

    var body: some View {
        HStack(spacing: Spacing.m) {
            PrismCategoryBadge(symbol: tab.symbol, module: tab.module, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.headerTitle)
                    .font(SpruceFont.headline)
                    .foregroundStyle(Ink.primary)
                Text(tab.subtitle)
                    .font(SpruceFont.callout)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Static, dimmed living canvas behind the settings form.
struct SettingsBackdrop: View {
    var module: ModuleID

    var body: some View {
        ZStack {
            Color(hex: 0x0B0B14)
            LivingCanvas(module: module, intensity: 0.55, animated: false)
            Color.black.opacity(0.22)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// Title with an optional explanation and leading symbol, used as a control label.
struct SettingsRowLabel: View {
    var title: String
    var detail: String? = nil
    var symbol: String? = nil
    /// Tints the symbol (defaults to secondary ink).
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s + 2) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint ?? Ink.secondary)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.primary)
                if let detail {
                    Text(detail)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Switch row: label on the left, switch on the right.
struct SettingsToggleRow: View {
    var title: String
    var detail: String? = nil
    var symbol: String? = nil
    var tint: Color? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: title, detail: detail, symbol: symbol, tint: tint)
        }
        .toggleStyle(.switch)
    }
}

/// A short warning or note line inside a section.
struct SettingsNote: View {
    var text: String
    var symbol: String = "exclamationmark.triangle.fill"
    var color: Color = StatusColor.warning

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Section header with a trailing detail ("12 of 17 included").
struct SettingsSectionHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }
}

/// Numbered instruction step ("1  Open System Settings").
struct SettingsStepRow: View {
    var number: Int
    var text: String
    var module: ModuleID

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s + 2) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.onBright)
                .frame(width: 18, height: 18)
                .background(Circle().fill(module.palette.accentText))
            Text(text)
                .font(SpruceFont.callout)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
