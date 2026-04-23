import SwiftUI

struct SplashView: View {
    @State private var gradientPhase: CGFloat = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DQ.Gradients.splash
                .ignoresSafeArea()
                .hueRotation(.degrees(reduceMotion ? 0 : gradientPhase * 30))

            VStack(spacing: DQ.Spacing.xl) {
                Image(systemName: "location.north.circle.fill")
                    .resizable()
                    .frame(width: DQ.Sizing.iconLarge, height: DQ.Sizing.iconLarge)
                    .foregroundStyle(DQ.Colors.accent)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .accessibilityLabel("Serendipity logo")

                Text("Serendipity")
                    .font(DQ.Typography.screenTitle())
                    .foregroundStyle(DQ.Colors.textPrimary)
                    .opacity(logoOpacity)

                ProgressView()
                    .tint(DQ.Colors.accent)
                    .accessibilityLabel("Loading")
            }
        }
        .onAppear {
            guard !reduceMotion else {
                logoScale = 1.0
                logoOpacity = 1.0
                return
            }
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: true)) {
                gradientPhase = 1.0
            }
        }
    }
}
