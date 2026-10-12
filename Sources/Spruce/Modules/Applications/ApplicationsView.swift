import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Applications module. CONTRACT: keep the type name `ApplicationsView` and `init()`.
struct ApplicationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .applications, actionTitle: "Soon", isEnabled: false) {}
    }
}
