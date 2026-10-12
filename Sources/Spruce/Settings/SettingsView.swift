import SpruceCore
import SpruceMac
import SwiftUI

/// Settings window. CONTRACT: keep `SettingsView`.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Text("Settings coming soon")
        }
        .padding()
        .frame(width: 560, height: 420)
    }
}
