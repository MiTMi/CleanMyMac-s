import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the Protection module. CONTRACT: keep the type name `ProtectionView` and `init()`.
struct ProtectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .protection, actionTitle: "Soon", isEnabled: false) {}
    }
}
