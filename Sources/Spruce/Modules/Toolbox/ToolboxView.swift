import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Toolbox module. CONTRACT: keep the type name `ToolboxView` and `init()`.
struct ToolboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .toolbox, actionTitle: "Soon", isEnabled: false) {}
    }
}
