import SpruceCore
import SpruceMac
import SwiftUI

/// Root view of the SpaceMap module. CONTRACT: keep the type name `SpaceMapView` and `init()`.
struct SpaceMapView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleIdleView(module: .spaceMap, actionTitle: "Soon", isEnabled: false) {}
    }
}
