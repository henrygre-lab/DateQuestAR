import SwiftUI
import ARKit
import RealityKit

struct RadarView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var matchManager: MatchManager
    @EnvironmentObject var locationService: LocationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var proximity: Double = 0.25          // miles
    @State private var showPhotos = false
    @State private var showIcebreaker = false
    @State private var arSessionActive = false
    @State private var blipPulse = false

    var body: some View {
        ZStack {
            // AR Camera feed or VoiceOver fallback
            if UIAccessibility.isVoiceOverRunning {
                voiceOverFallback
            } else {
                ARViewContainer(onSessionStart: { arSessionActive = true })
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            // HUD overlay
            VStack {
                topBar
                Spacer()
                radarRing
                Spacer()
                bottomPanel
            }
        }
        .onChange(of: matchManager.nearbyMatch) { _, match in
            guard let match else { return }
            proximity = match.status == .revealed ? 0.05 : 0.18
            showPhotos = match.status == .revealed
            if match.status == .icebreakerActive { showIcebreaker = true }
        }
        .onChange(of: proximity) { _, newDist in
            let intensity = locationService.hapticIntensity(for: newDist)
            locationService.playProximityHaptic(intensity: intensity)
        }
        .sheet(isPresented: $showIcebreaker) {
            if let challenge = matchManager.currentIcebreaker {
                IcebreakerView(challenge: challenge)
            }
        }
        .onAppear { blipPulse = true }
    }

    // MARK: - VoiceOver Fallback

    private var voiceOverFallback: some View {
        VStack(spacing: DQ.Spacing.xl) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: DQ.Sizing.iconLarge))
                .foregroundStyle(DQ.Colors.accent)
                .accessibilityHidden(true)
            Text("Audio Radar Mode")
                .font(DQ.Typography.sectionHeader())
                .foregroundStyle(DQ.Colors.textPrimary)
            Text("Distance to match: \(String(format: "%.2f", proximity)) miles")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.textSecondary)
                .accessibilityAddTraits(.updatesFrequently)
            if let match = matchManager.nearbyMatch {
                Text("Compatibility: \(Int(match.compatibilityScore * 100))%")
                    .font(DQ.Typography.body())
                    .foregroundStyle(DQ.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dqBackground()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DQ.Colors.textPrimary)
                    .shadow(color: .black.opacity(0.4), radius: 4)
            }
            .accessibilityLabel("Close radar")
            Spacer()
            Text("Radar")
                .font(DQ.Typography.cardTitle())
                .foregroundStyle(DQ.Colors.textPrimary)
                .shadow(color: .black.opacity(0.4), radius: 4)
            Spacer()
            if let match = matchManager.nearbyMatch {
                Text("\(Int(match.compatibilityScore * 100))% Match")
                    .font(DQ.Typography.caption().bold())
                    .padding(.horizontal, DQ.Spacing.sm)
                    .padding(.vertical, DQ.Spacing.xxxs)
                    .background(DQ.Colors.accent)
                    .clipShape(Capsule())
                    .foregroundStyle(DQ.Colors.textPrimary)
                    .accessibilityLabel("\(Int(match.compatibilityScore * 100)) percent compatibility")
            }
        }
        .padding()
        .background(DQ.Gradients.topFade)
    }

    // MARK: - Radar Ring Animation

    private var radarRing: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(DQ.Colors.accent.opacity(0.3 - Double(i) * 0.08), lineWidth: 1)
                    .frame(width: CGFloat(120 + i * 60), height: CGFloat(120 + i * 60))
                    .scaleEffect(arSessionActive ? 1.0 : 0.8)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(Double(i) * 0.3),
                        value: arSessionActive
                    )
            }
            .accessibilityHidden(true)

            // Center blip
            Circle()
                .fill(DQ.Colors.accent)
                .frame(width: DQ.Sizing.radarBlipSize, height: DQ.Sizing.radarBlipSize)
                .shadow(color: DQ.Colors.accent, radius: blipPulse ? 16 : 8)
                .scaleEffect(blipPulse ? 1.3 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: blipPulse
                )
                .accessibilityHidden(true)

            // Distance label
            Text(String(format: "%.2f mi", proximity))
                .font(DQ.Typography.caption().bold())
                .foregroundStyle(DQ.Colors.textPrimary)
                .padding(.top, DQ.Sizing.timerRingSize)
                .accessibilityLabel("Distance: \(String(format: "%.2f", proximity)) miles")
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: DQ.Spacing.xl) {
            proximityBar

            if showPhotos {
                photoRevealSection
            } else {
                Text("Get closer to reveal photos...")
                    .font(DQ.Typography.body())
                    .foregroundStyle(DQ.Colors.textSecondary)
            }
        }
        .padding()
        .background(DQ.Gradients.bottomFade)
    }

    private var proximityBar: some View {
        VStack(spacing: DQ.Spacing.xxs) {
            Text("Proximity")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DQ.Radii.small)
                        .fill(DQ.Colors.surfaceElevated)
                    RoundedRectangle(cornerRadius: DQ.Radii.small)
                        .fill(DQ.Gradients.proximity)
                        .frame(width: geo.size.width * CGFloat(1.0 - (proximity / 0.25)))
                }
            }
            .frame(height: DQ.Spacing.xs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Proximity: \(Int((1.0 - proximity / 0.25) * 100)) percent")
            HStack {
                Text("0.25 mi")
                    .font(DQ.Typography.captionSmall())
                    .foregroundStyle(DQ.Colors.textPlaceholder)
                Spacer()
                Text("0 mi")
                    .font(DQ.Typography.captionSmall())
                    .foregroundStyle(DQ.Colors.textPlaceholder)
            }
        }
    }

    private var photoRevealSection: some View {
        VStack(spacing: DQ.Spacing.md) {
            HStack(spacing: DQ.Spacing.xxxs) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(DQ.Colors.textPrimary)
                Text("Photos Revealed!")
                    .font(DQ.Typography.cardTitle())
                    .foregroundStyle(DQ.Colors.textPrimary)
            }
            HStack(spacing: DQ.Spacing.sm) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DQ.Radii.medium)
                        .fill(DQ.Colors.accentSubtle)
                        .frame(width: 80, height: 100)
                        .overlay(Image(systemName: "person.fill")
                            .font(.largeTitle).foregroundStyle(DQ.Colors.accentSecondary))
                        .overlay(alignment: .bottomTrailing) {
                            TrustBadgeView(
                                trustLevel: matchManager.nearbyMatchProfile?.trustLevel ?? .bronze,
                                size: .small
                            )
                            .offset(x: 4, y: 4)
                        }
                        .accessibilityLabel("Match photo placeholder")
                }
            }
            Button("Start Icebreaker") {
                showIcebreaker = true
            }
            .buttonStyle(.dqPrimary)
            .accessibilityHint("Launches an icebreaker challenge with your match")
        }
    }
}

// MARK: - ARViewContainer (UIViewRepresentable)

struct ARViewContainer: UIViewRepresentable {
    var onSessionStart: () -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> ARCoordinator {
        ARCoordinator(onSessionStart: onSessionStart)
    }
}

// MARK: - ARCoordinator

final class ARCoordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
    var onSessionStart: () -> Void
    private var sessionStarted = false

    init(onSessionStart: @escaping () -> Void) {
        self.onSessionStart = onSessionStart
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !sessionStarted else { return }
        sessionStarted = true
        DispatchQueue.main.async { self.onSessionStart() }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[ARKit] Session failed: \(error.localizedDescription)")
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        // TODO: Add AR directional hints/overlays as SCNNodes
        return nil
    }
}
