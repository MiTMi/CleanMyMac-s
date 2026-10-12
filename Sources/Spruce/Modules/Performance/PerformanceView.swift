import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Performance module. CONTRACT: keep the type name `PerformanceView` and `init()`.
struct PerformanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .performance, actionTitle: "Soon", isEnabled: false) {}
    }
}
