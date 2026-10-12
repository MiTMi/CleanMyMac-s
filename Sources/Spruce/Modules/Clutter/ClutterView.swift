import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Clutter module. CONTRACT: keep the type name `ClutterView` and `init()`.
struct ClutterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .clutter, actionTitle: "Soon", isEnabled: false) {}
    }
}
