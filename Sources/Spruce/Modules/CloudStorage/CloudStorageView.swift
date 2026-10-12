import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the CloudStorage module. CONTRACT: keep the type name `CloudStorageView` and `init()`.
struct CloudStorageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .cloudStorage, actionTitle: "Soon", isEnabled: false) {}
    }
}
