import SpruceCore
import SpruceMac
import SwiftUI

/// Menu bar popover. CONTRACT: keep `MonitorMenuView` and `MonitorMenuLabel`.
struct MonitorMenuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spruce").font(.headline)
            Text("Monitor coming soon").foregroundStyle(.secondary)
            Divider()
            Button("Quit Spruce") { NSApp.terminate(nil) }
        }
        .padding()
        .frame(width: 320)
    }
}

/// The status item shown in the menu bar.
struct MonitorMenuLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(systemName: "leaf")
    }
}
