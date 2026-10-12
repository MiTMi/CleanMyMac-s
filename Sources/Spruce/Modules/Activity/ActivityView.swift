import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Activity module. CONTRACT: keep the type name `ActivityView` and `init()`.
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .activity, actionTitle: "Soon", isEnabled: false) {}
    }
}
