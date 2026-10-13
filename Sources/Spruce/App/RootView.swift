import SpruceCore
import SpruceMac
import SwiftUI

/// Main window: living canvas behind a frosted sidebar rail and the module content.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            LivingCanvas(module: model.selection)
            HStack(spacing: 0) {
                SidebarRail()
                    .padding(10)
                ModuleHost(module: model.selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(model.selection)
                    .transition(.opacity)
            }
        }
        .animation(Motion.canvas, value: model.selection)
        .onAppear {
            model.registerWindowOpener(openWindow)
            showOnboarding = !model.settings.settings.hasCompletedOnboarding
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                model.settings.settings.hasCompletedOnboarding = true
                showOnboarding = false
            }
            .environment(model)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }
}

/// Routes the selected module to its root view.
struct ModuleHost: View {
    var module: ModuleID

    var body: some View {
        switch module {
        case .checkup: CheckupView()
        case .cleanup: CleanupView()
        case .protection: ProtectionView()
        case .performance: PerformanceView()
        case .applications: ApplicationsView()
        case .clutter: ClutterView()
        case .spaceMap: SpaceMapView()
        case .cloudStorage: CloudStorageView()
        case .toolbox: ToolboxView()
        case .activity: ActivityView()
        }
    }
}

/// Frosted, in-window navigation rail.
struct SidebarRail: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Room for the traffic-light buttons of the hidden title bar.
            Color.clear.frame(height: 26)
            ForEach(ModuleID.Section.allCases, id: \.self) { section in
                if section != .overview {
                    SectionHeader(title: section.rawValue)
                        .padding(.horizontal, Spacing.m)
                        .padding(.top, Spacing.m)
                        .padding(.bottom, Spacing.xxs)
                }
                ForEach(section.modules) { module in
                    railItem(module)
                }
            }
            Spacer()
            if !model.hasFullDiskAccess {
                Button {
                    Permissions.openFullDiskAccessSettings()
                } label: {
                    Label("Grant Full Disk Access", systemImage: "lock.open")
                        .font(SpruceFont.caption.weight(.medium))
                        .foregroundStyle(StatusColor.warning)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.m)
            }
            SidebarHealthPill()
                .padding(.horizontal, Spacing.xs)
            HStack(spacing: Spacing.m) {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Ink.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
                SidebarInboxButton()
                Spacer()
            }
            .padding(Spacing.m)
        }
        .frame(width: 214)
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Ink.hairline))
    }

    private func railItem(_ module: ModuleID) -> some View {
        let selected = model.selection == module
        return Button {
            model.open(module)
        } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: module.palette.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? module.palette.accentText : Ink.secondary)
                    .frame(width: 20)
                Text(module.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                Spacer()
                if module == .checkup {
                    SidebarCheckupBadge()
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Ink.selectedFill)
                        .matchedGeometryEffect(id: "rail-selection", in: selectionNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.xs)
        .animation(Motion.standard, value: model.selection)
    }
}

/// Small live progress ring on the Checkup rail item while a Checkup scan or run is busy.
private struct SidebarCheckupBadge: View {
    private var session: CheckupSession { CheckupSession.shared }

    var body: some View {
        if session.isBusy {
            ProgressRing(progress: session.displayedFraction > 0 ? session.displayedFraction : nil,
                         module: .checkup, lineWidth: 2)
                .frame(width: 14, height: 14)
                .help("Checkup in progress")
                .transition(.opacity)
        }
    }
}

/// Mac Health at the foot of the sidebar: the same score as Activity's gauge.
private struct SidebarHealthPill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let report = model.healthReport
        let color = report.isRated ? Self.color(report.level) : PrismInk(contrast).tertiary
        Button {
            model.open(.activity)
        } label: {
            HStack(spacing: Spacing.s) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .shadow(color: color.opacity(0.6), radius: report.isRated ? 3 : 0)
                Text("Health")
                    .font(SpruceFont.caption.weight(.medium))
                    .foregroundStyle(Ink.secondary)
                Text(report.isRated ? report.level.title : "Not rated yet")
                    .font(SpruceFont.caption.weight(.semibold))
                    .foregroundStyle(report.isRated ? Ink.primary : PrismInk(contrast).tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if report.isRated {
                    Text("\(report.score)")
                        .font(SpruceFont.captionDigits)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 7)
            .background(Ink.subtleFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(report.isRated ? "Mac Health \(report.score) · \(report.level.blurb)" : "Mac Health is rated after the first measurements")
        .accessibilityLabel(report.isRated ? "Mac Health \(report.level.title), \(report.score)" : "Mac Health not rated yet")
    }

    static func color(_ level: ActivityHealthLevel) -> Color {
        switch level {
        case .excellent, .good: return StatusColor.success
        case .fair, .requiresAttention: return StatusColor.warning
        case .critical: return StatusColor.danger
        }
    }
}

/// The bell: opens the in-app Notification Center. A dot (no count) marks unread items.
private struct SidebarInboxButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showsInbox.toggle()
        } label: {
            Image(systemName: "bell")
                .foregroundStyle(Ink.secondary)
                .overlay(alignment: .topTrailing) {
                    if model.inbox.hasUnread {
                        Circle()
                            .fill(StatusColor.info)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("Notifications")
        .accessibilityLabel(model.inbox.hasUnread ? "Notifications, unread" : "Notifications")
        .popover(isPresented: Binding(get: { model.showsInbox }, set: { model.showsInbox = $0 }),
                 arrowEdge: .trailing) {
            InboxView()
                .environment(model)
        }
    }
}
