import SwiftUI

/// Lightweight radar visualization for the home dashboard.
/// Shows concentric rings with dot blips — animated when Quest Mode is ON.
struct HomeRadarPreview: View {
    var isActive: Bool
    var nearbyCount: Int

    @State private var rotationAngle: Double = 0
    @State private var blipPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Fixed blip positions (angle in degrees, radius fraction 0…1)
    private let blipPositions: [(angle: Double, radius: Double)] = [
        (35, 0.3), (110, 0.55), (200, 0.7), (280, 0.4), (330, 0.85)
    ]

    var body: some View {
        VStack(spacing: DQ.Spacing.md) {
            Text("Nearby Quests")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DQ.Colors.textPrimary)

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = size / 2
                let maxRingRadius = size * 0.45

                ZStack {
                    // Concentric rings
                    ForEach(1...4, id: \.self) { ring in
                        let fraction = Double(ring) / 4.0
                        Circle()
                            .stroke(
                                Color.white.opacity(0.08 + fraction * 0.06),
                                lineWidth: 0.5
                            )
                            .frame(
                                width: maxRingRadius * 2 * fraction,
                                height: maxRingRadius * 2 * fraction
                            )
                    }

                    // Sweep line when active
                    if isActive {
                        SweepLine(radius: maxRingRadius)
                            .rotationEffect(.degrees(rotationAngle))
                    }

                    // Center "You" dot
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: DQ.Colors.accent.opacity(0.6), radius: 6)

                    // Blip dots
                    ForEach(Array(blipPositions.enumerated()), id: \.offset) { index, blip in
                        let r = blip.radius * maxRingRadius
                        let angle = Angle.degrees(blip.angle + (isActive ? rotationAngle * 0.05 * Double(index % 3) : 0))
                        let x = r * cos(angle.radians)
                        let y = r * sin(angle.radians)

                        Circle()
                            .fill(isActive ? blipColor(for: index) : Color.white.opacity(0.2))
                            .frame(width: blipSize(for: index), height: blipSize(for: index))
                            .scaleEffect(isActive && blipPulse ? 1.3 : 1.0)
                            .opacity(isActive ? (blipPulse ? 1.0 : 0.6) : 0.3)
                            .offset(x: x, y: y)
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(height: 240)

            Text("\(nearbyCount) compatible within 0.25 mi")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DQ.Colors.textQuaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DQ.Spacing.lg)
        .padding(.horizontal, DQ.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DQ.Radii.xl)
                .fill(DQ.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DQ.Radii.xl)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear { startAnimations() }
        .onChange(of: isActive) { _ in startAnimations() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Radar showing \(nearbyCount) nearby potential matches")
    }

    // MARK: - Helpers

    private func blipColor(for index: Int) -> Color {
        [DQ.Colors.accent, DQ.Colors.accentPink, DQ.Colors.accent.opacity(0.8),
         DQ.Colors.accentPink.opacity(0.7), DQ.Colors.accent][index % 5]
    }

    private func blipSize(for index: Int) -> CGFloat {
        [8, 6, 7, 5, 6][index % 5]
    }

    private func startAnimations() {
        guard !reduceMotion else { return }
        if isActive {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                blipPulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                rotationAngle = 0
                blipPulse = false
            }
        }
    }
}

// MARK: - Sweep Line Shape

private struct SweepLine: View {
    let radius: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [DQ.Colors.accent.opacity(0.5), .clear],
                    startPoint: .bottom, endPoint: .top
                )
            )
            .frame(width: 1.5, height: radius)
            .offset(y: -radius / 2)
    }
}
