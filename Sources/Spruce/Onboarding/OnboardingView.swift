import SpruceCore
import SpruceMac
import SwiftUI

/// First-launch onboarding. CONTRACT: keep `OnboardingView(onFinish:)`.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Spruce").font(.title)
            Button("Get Started", action: onFinish)
        }
        .padding(40)
        .frame(width: 560, height: 420)
    }
}
