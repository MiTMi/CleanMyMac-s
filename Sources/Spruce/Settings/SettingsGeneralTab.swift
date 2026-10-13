import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// General: login item, menu bar monitor, sounds, ambient motion, welcome guide.
struct SettingsGeneralTab: View {
    @Bindable var store: SettingsStore
    @Environment(AppModel.self) private var model

    @State private var loginState: SettingsLaunchState = .off
    @State private var loginError: String?
    @State private var showingWelcome = false
    @State private var systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        SettingsPage(tab: .general) {
            startupSection
            menuBarSection
            soundSection
            motionSection
            welcomeSection
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .sheet(isPresented: $showingWelcome) {
            OnboardingView {
                showingWelcome = false
            }
            .environment(model)
        }
    }

    // MARK: Sections

    private var startupSection: some View {
        Section {
            SettingsToggleRow(title: "Open Spruce at login",
                              detail: "Spruce starts with your Mac, so alerts and real-time protection keep working.",
                              symbol: "power", isOn: launchBinding)
            if loginState == .needsApproval {
                HStack {
                    SettingsNote(text: "macOS is waiting for your approval in System Settings › General › Login Items.")
                    Button("Open Login Items") { Permissions.openLoginItemsSettings() }
                        .controlSize(.small)
                }
            }
            if let loginError {
                SettingsNote(text: loginError, symbol: "xmark.octagon.fill", color: StatusColor.danger)
            }
        } header: {
            Text("Startup")
        }
    }

    private var menuBarSection: some View {
        Section {
            SettingsToggleRow(title: "Show monitor in the menu bar",
                              detail: "Live CPU, memory, storage and network at a glance, with one-click fixes.",
                              symbol: "menubar.rectangle", isOn: $store.settings.showMenuBarMonitor)
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("Alerts keep working while Spruce runs, even with the menu bar icon hidden.")
        }
    }

    private var soundSection: some View {
        Section {
            HStack(spacing: Spacing.m) {
                SettingsToggleRow(title: "Play sounds",
                                  detail: "Soft cues when a scan starts, finishes or needs your attention.",
                                  symbol: "speaker.wave.2", isOn: $store.settings.playSounds)
                Button("Preview") { SpruceSound.play(.scanComplete, force: true) }
                    .controlSize(.small)
                    .disabled(!store.settings.playSounds || !SpruceSound.systemUISoundsEnabled)
            }
            if store.settings.playSounds && !SpruceSound.systemUISoundsEnabled {
                SettingsNote(text: "“Play user interface sound effects” is off in System Settings › Sound, so Spruce stays silent.",
                             symbol: "speaker.slash.fill", color: StatusColor.info)
            }
        } header: {
            Text("Sound")
        }
    }

    private var motionSection: some View {
        Section {
            SettingsToggleRow(title: "Reduce ambient motion",
                              detail: "Stops the drifting background, particles and breathing glows. Progress animations stay.",
                              symbol: "wind", isOn: $store.settings.reduceAmbientMotion)
            if systemReducesMotion {
                SettingsNote(text: "Reduce Motion is on in System Settings › Accessibility, so ambient motion is already reduced.",
                             symbol: "figure.walk.motion", color: StatusColor.info)
            }
        } header: {
            Text("Motion")
        }
    }

    private var welcomeSection: some View {
        Section {
            HStack {
                SettingsRowLabel(title: "Welcome guide",
                                 detail: "Walk through permissions, alerts and the safety basics again.",
                                 symbol: "hand.wave")
                Spacer()
                Button("Show Welcome Guide…") { showingWelcome = true }
            }
        }
    }

    // MARK: Login item

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { loginState.isRequested },
            set: { enabled in
                loginError = SettingsLoginItem.set(enabled, store: store)
                loginState = SettingsLoginItem.state
            }
        )
    }

    private func refresh() {
        loginState = SettingsLoginItem.syncStoredValue(store)
        systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
