import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Checkup module. CONTRACT: keep the type name `CheckupView` and `init()`.
struct CheckupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .checkup, actionTitle: "Soon", isEnabled: false) {}
    }
}
