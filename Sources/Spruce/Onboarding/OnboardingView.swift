import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// First-launch onboarding. CONTRACT: keep `OnboardingView(onFinish:)`.
///
/// A paged sheet (640 × 500) on a living Prism canvas: Welcome → Safety promise →
/// Full Disk Access → Alerts, menu bar & login → Ready. Every permission can be skipped;
/// nothing is scanned or changed until the user starts a Checkup.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onFinish: () -> Void

    @State private var flow = OnboardingFlow()

    var body: some View {
        ZStack {
            OnboardingBackdrop(module: flow.step.module)
            VStack(spacing: 0) {
                topBar
                pageHost
                bottomBar
            }
        }
        .frame(width: OnboardingLayout.width, height: OnboardingLayout.height)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            flow.loginState = SettingsLoginItem.syncStoredValue(model.settings)
            await flow.refreshNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
            flow.loginState = SettingsLoginItem.state
            Task { await flow.refreshNotifications() }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            if flow.step != .welcome {
                PrismBackButton(title: "Back") { go(back: true) }
                    .transition(.opacity)
            }
            Spacer()
            if flow.step != .ready {
                Button("Skip Setup") { finish(runCheckup: false) }
                    .buttonStyle(.plain)
                    .font(SpruceFont.callout.weight(.medium))
                    .foregroundStyle(Ink.tertiary)
                    .help("Close the welcome guide. You can reopen it from Settings › General.")
            }
        }
        .frame(height: 30)
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
    }

    private var pageHost: some View {
        ZStack {
            page
                .id(flow.step)
                .transition(pageTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var page: some View {
        switch flow.step {
        case .welcome:
            OnboardingWelcomePage()
        case .safety:
            OnboardingSafetyPage()
        case .fullDiskAccess:
            OnboardingAccessPage(flow: flow, onGranted: { advanceAfterGrant() })
        case .stayInformed:
            OnboardingStayInformedPage(flow: flow)
        case .ready:
            OnboardingReadyPage(flow: flow)
        }
    }

    private var bottomBar: some View {
        let primary = primaryAction
        return HStack(spacing: Spacing.s) {
            OnboardingProgressDots(count: OnboardingStep.allCases.count, index: flow.step.rawValue,
                                   module: flow.step.module)
            Spacer()
            if let secondary = secondaryAction {
                Button(secondary.title, action: secondary.run)
                    .buttonStyle(PrismCapsuleButtonStyle(role: .secondary, large: true))
            }
            Button(action: primary.run) {
                HStack(spacing: 6) {
                    if primary.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Text(primary.title)
                    if let symbol = primary.symbol {
                        Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                    }
                }
            }
            .buttonStyle(PrismCapsuleButtonStyle(role: .primary, large: true))
            .keyboardShortcut(.defaultAction)
            .disabled(primary.isBusy)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
        .padding(.top, Spacing.s)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let offset: CGFloat = flow.movingForward ? 36 : -36
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: offset)),
                           removal: .opacity.combined(with: .offset(x: -offset)))
    }

    // MARK: Actions per step

    private var primaryAction: OnboardingAction {
        switch flow.step {
        case .welcome:
            return OnboardingAction(title: "Get Started", symbol: "arrow.right") { go() }
        case .safety:
            return OnboardingAction(title: "Sounds Good", symbol: "arrow.right") { go() }
        case .fullDiskAccess:
            if model.hasFullDiskAccess {
                return OnboardingAction(title: "Continue", symbol: "arrow.right") { go() }
            }
            return OnboardingAction(title: flow.openedPrivacySettings ? "Open System Settings Again" : "Open System Settings") {
                flow.openedPrivacySettings = true
                // Touch a protected file first so macOS lists Spruce under Full Disk Access.
                model.refreshPermissions()
                Permissions.openFullDiskAccessSettings()
            }
        case .stayInformed:
            if flow.notificationStatus == .notDetermined {
                return OnboardingAction(title: "Allow Notifications", isBusy: flow.isRequestingNotifications) {
                    Task {
                        await flow.requestNotifications()
                        go()
                    }
                }
            }
            return OnboardingAction(title: "Continue", symbol: "arrow.right") { go() }
        case .ready:
            return OnboardingAction(title: "Run Your First Checkup", symbol: "sparkles") { finish(runCheckup: true) }
        }
    }

    private var secondaryAction: OnboardingAction? {
        switch flow.step {
        case .welcome, .safety:
            return nil
        case .fullDiskAccess:
            if model.hasFullDiskAccess { return nil }
            return OnboardingAction(title: "Skip for Now") { go() }
        case .stayInformed:
            if flow.notificationStatus != .notDetermined { return nil }
            return OnboardingAction(title: "Not Now") { go() }
        case .ready:
            return OnboardingAction(title: "Look Around First") { finish(runCheckup: false) }
        }
    }

    // MARK: Navigation

    private func go(back: Bool = false) {
        let target = OnboardingStep(rawValue: flow.step.rawValue + (back ? -1 : 1))
        guard let target else { return }
        flow.movingForward = !back
        withAnimation(reduceMotion ? Motion.fade : Motion.emphasized) {
            flow.step = target
        }
    }

    /// Full Disk Access was granted while the access page was showing: move on by itself.
    private func advanceAfterGrant() {
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if flow.step == .fullDiskAccess { go() }
        }
    }

    /// Marks onboarding complete; "Run First Checkup" also opens Checkup and starts a scan.
    private func finish(runCheckup: Bool) {
        model.settings.settings.hasCompletedOnboarding = true
        SettingsReminderScheduler.sync(model.settings.settings)
        if runCheckup {
            model.open(.checkup, tool: "checkup.scan")
            openWindow(id: "main")
        }
        onFinish()
    }
}

// MARK: - Flow state

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case safety
    case fullDiskAccess
    case stayInformed
    case ready

    var id: Int { rawValue }

    /// Palette for the canvas and accents of each page.
    var module: ModuleID {
        switch self {
        case .welcome: return .checkup
        case .safety: return .protection
        case .fullDiskAccess: return .applications
        case .stayInformed: return .performance
        case .ready: return .checkup
        }
    }
}

@MainActor
@Observable
final class OnboardingFlow {
    var step: OnboardingStep = .welcome
    var movingForward = true
    var notificationStatus: SettingsNotificationStatus = .notDetermined
    var isRequestingNotifications = false
    /// The user opened System Settings from the access page (enables auto-advance on grant).
    var openedPrivacySettings = false
    var loginState: SettingsLaunchState = .off
    var loginError: String?

    init() {}

    func refreshNotifications() async {
        notificationStatus = await SettingsNotificationAccess.status()
    }

    func requestNotifications() async {
        isRequestingNotifications = true
        notificationStatus = await SettingsNotificationAccess.request()
        isRequestingNotifications = false
    }
}

struct OnboardingAction {
    var title: String
    var symbol: String? = nil
    var isBusy: Bool = false
    var run: () -> Void
}

enum OnboardingLayout {
    static let width: CGFloat = 640
    static let height: CGFloat = 500
}

// MARK: - Chrome components

/// Living canvas behind the pages, tinted per step.
struct OnboardingBackdrop: View {
    var module: ModuleID

    var body: some View {
        ZStack {
            Color(hex: 0x0B0B14)
            LivingCanvas(module: module, intensity: 0.9)
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.28)],
                           startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Progress dots: the current step is a stretched capsule in the page accent.
struct OnboardingProgressDots: View {
    var count: Int
    var index: Int
    var module: ModuleID

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? module.palette.accent : Color.white.opacity(i < index ? 0.55 : 0.22))
                    .frame(width: i == index ? 20 : 6, height: 6)
            }
        }
        .animation(Motion.standard, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}
