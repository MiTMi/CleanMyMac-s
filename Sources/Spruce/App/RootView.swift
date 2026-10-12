import SpruceCore
import SpruceMac
import SwiftUI

/// Main window: living canvas behind a frosted sidebar rail and the module content.
struct RootView: View {
    @Environment(AppModel.self) private var model
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
            HStack {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Ink.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
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
