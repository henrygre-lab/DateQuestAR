import SwiftUI

struct DQBackground: View {
    var gradient: Bool = false
    var heroGlow: Bool = false

    var body: some View {
        ZStack {
            DQ.Colors.backgroundPrimary.ignoresSafeArea()
            if gradient {
                DQ.Gradients.background.ignoresSafeArea()
            }
            if heroGlow {
                DQ.Gradients.heroOverlay.ignoresSafeArea()
            }
        }
    }
}

extension View {
    func dqBackground(gradient: Bool = false, heroGlow: Bool = false) -> some View {
        background { DQBackground(gradient: gradient, heroGlow: heroGlow) }
    }
}
