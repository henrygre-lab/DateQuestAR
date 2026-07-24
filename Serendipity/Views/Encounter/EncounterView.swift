// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] DEBUG-only: entire view compiles out of release builds
// [x] Displays only the mock demo persona — no real user PII
// [x] Full identity (name/bio) gated behind RevealStage == .connected, mirroring
//     the production reveal contract (Risk #3 mitigation stays visible in the demo)

#if DEBUG
import SwiftUI

/// Developer Bypass walkthrough surface. Visualizes the full encounter stage
/// machine — proximity alert → progressive unblur → NameDrop → full profile +
/// rating — driven entirely by `MatchManager`'s in-memory demo layer.
///
/// Visual rebuild: dark-only, high-contrast mono surfaces with a single signal
/// accent. Structure is composed from reusable components (StageStepper,
/// RevealHero, VibeScoreBreakdown, TierUpgradeBanner); all demo behavior,
/// the stage machine, and the revealProgress math are unchanged.
struct EncounterView: View {
    @EnvironmentObject var matchManager: MatchManager
    @ObservedObject private var revealManager = RevealManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeChallenge: IcebreakerChallenge?
    @State private var demoRating = 0
    @State private var revealedTrust: UserProfile.TrustLevel?

    // MARK: - Derived State

    private var match: Match? { matchManager.nearbyMatch }
    private var partner: UserProfile? { matchManager.nearbyMatchProfile }

    private var session: EncounterSession? {
        guard let id = match?.id else { return nil }
        return revealManager.activeSessions[id]
    }

    private var stage: RevealStage {
        session?.revealStage ?? match?.revealStage ?? .blurred
    }

    private var revealProgress: Double {
        session?.revealProgress ?? 0.0
    }

    /// True once the 10–15 min EncounterSession window has elapsed before the
    /// pair connected. Mirrors the production timeout so the demo can't sit in a
    /// frozen half-revealed state.
    private var sessionExpired: Bool {
        guard let session, stage < .connected else { return false }
        return !session.isActive()
    }

    private var shownTrust: UserProfile.TrustLevel {
        revealedTrust ?? partner?.trustLevel ?? .bronze
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [DQ.Colors.mono50, DQ.Colors.mono0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: DQ.Spacing.xl) {
                header
                if match == nil || partner == nil {
                    Spacer(); loadingState; Spacer()
                } else if sessionExpired {
                    Spacer(); expiredState; Spacer()
                } else {
                    StageStepper(current: stage)
                    RevealHero(name: partner?.displayName ?? "Match",
                               progress: revealProgress,
                               stage: stage,
                               trust: shownTrust)
                    Spacer(minLength: 0)
                    contextPanel
                    ctaPanel
                }
            }
            .padding(.horizontal, DQ.Spacing.xl)
            .padding(.vertical, DQ.Spacing.lg)
        }
        .sheet(item: $activeChallenge) { challenge in
            IcebreakerView(challenge: challenge, isDemo: true) {
                matchManager.completeDemoIcebreaker()
                activeChallenge = nil
            }
            .environmentObject(matchManager)
        }
        .animation(reduceMotion ? nil : DQ.Anim.standard, value: stage)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: revealProgress)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { matchManager.endDemoEncounter() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DQ.Colors.mono700)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DQ.Colors.mono200))
            }
            .accessibilityLabel("End demo encounter")

            Spacer()

            Text("Live encounter")
                .font(DQ.Typography.cardTitle())
                .foregroundStyle(DQ.Colors.mono900)

            Spacer()

            if let score = match?.compatibilityScore {
                Text("\(Int(score * 100))%")
                    .font(DQ.Typography.mono(13, weight: .bold))
                    .foregroundStyle(DQ.Colors.signal)
                    .padding(.horizontal, DQ.Spacing.sm)
                    .padding(.vertical, DQ.Spacing.xxxs)
                    .background(Capsule().fill(DQ.Colors.signalSubtle))
                    .accessibilityLabel("\(Int(score * 100)) percent compatibility")
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
    }

    // MARK: - Empty / Error States

    private var loadingState: some View {
        VStack(spacing: DQ.Spacing.md) {
            ProgressView().tint(DQ.Colors.signal)
            Text("Finding a match nearby…")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.mono700)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finding a match nearby")
    }

    private var expiredState: some View {
        VStack(spacing: DQ.Spacing.lg) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 44))
                .foregroundStyle(DQ.Colors.mono600)
            Text("Encounter window closed")
                .font(DQ.Typography.sectionHeader())
                .foregroundStyle(DQ.Colors.mono900)
            Text("Encounter sessions stay live for 10–15 minutes, then expire to keep things ephemeral and private.")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.mono600)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Close") { matchManager.endDemoEncounter() }
                .buttonStyle(.dqSignal)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DQ.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Encounter window closed. Sessions expire after 10 to 15 minutes.")
    }

    // MARK: - Context Panel (vibes / score / prompts)

    @ViewBuilder
    private var contextPanel: some View {
        switch stage {
        case .blurred:
            if let bd = match?.scoreBreakdown {
                VibeScoreBreakdown(vibes: partner?.intentVibes ?? [], breakdown: bd)
            }
        case .partial:
            caption("Unblurring as you break the ice…")
        case .revealed:
            caption("Vibe passed. Ready to swap contacts?")
        case .connected:
            connectedContext
        }
    }

    private var connectedContext: some View {
        VStack(spacing: DQ.Spacing.sm) {
            if let bio = partner?.bio {
                Text(bio)
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.mono700)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if revealedTrust == .platinum {
                TierUpgradeBanner(level: .platinum)
                    .transition(.opacity)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DQ.Typography.body())
            .foregroundStyle(DQ.Colors.mono700)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - CTA Panel

    @ViewBuilder
    private var ctaPanel: some View {
        switch stage {
        case .blurred:
            if matchManager.demoReadyForIcebreaker {
                VStack(spacing: DQ.Spacing.sm) {
                    Text("Start an icebreaker")
                        .font(DQ.Typography.caption())
                        .foregroundStyle(DQ.Colors.mono600)
                    HStack(spacing: DQ.Spacing.md) {
                        icebreakerButton("Trivia", "questionmark.bubble", .trivia)
                        icebreakerButton("Word chain", "arrow.triangle.branch", .wordAssociation)
                    }
                }
            } else {
                approachIndicator
            }
        case .partial:
            Text("Icebreaker in progress…")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.mono600)
                .frame(maxWidth: .infinity)
        case .revealed:
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                matchManager.demoNameDrop()
            } label: {
                Label("NameDrop to connect", systemImage: "wave.3.right")
            }
            .buttonStyle(.dqSignal)
        case .connected:
            ratingPanel
        }
    }

    private var approachIndicator: some View {
        VStack(spacing: DQ.Spacing.xs) {
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundStyle(DQ.Colors.mono700)
                Text("Match approaching")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.mono700)
                Spacer()
                Text(String(format: "%.2f mi", matchManager.demoDistanceMiles))
                    .font(DQ.Typography.mono(13, weight: .semibold))
                    .foregroundStyle(DQ.Colors.mono900)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DQ.Colors.mono300)
                    Capsule().fill(DQ.Colors.signal)
                        .frame(width: geo.size.width * CGFloat(1.0 - (matchManager.demoDistanceMiles / 0.25)))
                }
            }
            .frame(height: 6)
        }
    }

    private func icebreakerButton(_ title: String, _ icon: String, _ type: IcebreakerChallenge.ChallengeType) -> some View {
        Button {
            matchManager.startDemoIcebreaker(type: type)
            activeChallenge = matchManager.currentIcebreaker
        } label: {
            VStack(spacing: DQ.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DQ.Colors.signal)
                Text(title)
                    .font(DQ.Typography.caption().bold())
                    .foregroundStyle(DQ.Colors.mono900)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(RoundedRectangle(cornerRadius: DQ.Radii.large).fill(DQ.Colors.mono100))
            .overlay(RoundedRectangle(cornerRadius: DQ.Radii.large).stroke(DQ.Colors.mono300, lineWidth: 1))
        }
        .accessibilityLabel("Start \(title) icebreaker")
    }

    private var ratingPanel: some View {
        VStack(spacing: DQ.Spacing.sm) {
            Text("Did they look like their photos?")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.mono600)
            HStack(spacing: DQ.Spacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(DQ.Anim.quick) { demoRating = star }
                        let level = matchManager.submitDemoRating(star)
                        withAnimation(DQ.Anim.spring) { revealedTrust = level }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: star <= demoRating ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundStyle(star <= demoRating ? DQ.Colors.trustGold : DQ.Colors.mono500)
                    }
                    .accessibilityLabel("\(star) star")
                }
            }
            Button("Finish") { matchManager.endDemoEncounter() }
                .foregroundStyle(DQ.Colors.mono600)
                .font(DQ.Typography.caption())
        }
    }
}
#endif
