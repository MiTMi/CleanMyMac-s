import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Cleanup module. CONTRACT: keep the type name `CleanupView` and `init()`.
struct CleanupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .cleanup, actionTitle: "Soon", isEnabled: false) {}
    }
}
