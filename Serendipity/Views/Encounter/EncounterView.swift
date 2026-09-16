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
/// DesignSystem v2 skin (docs/DESIGN_SYSTEM.md §5–§6): top bar → StageStepper →
/// RevealHero → score card (stages 1–3) or rating + tier upgrade (stage 4) →
/// primary CTA → safety line. All demo behavior, the stage machine, and the
/// `revealProgress` math are unchanged; only the presentation moved.
struct EncounterView: View {
    @EnvironmentObject var matchManager: MatchManager
    @ObservedObject private var revealManager = RevealManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    @State private var activeChallenge: IcebreakerChallenge?
    @State private var demoRating = 0
    @State private var revealedTrust: UserProfile.TrustLevel?
    /// Which icebreaker the CTA will launch. Pre-selected so stage 1 stays a
    /// single primary pill (§6.1).
    @State private var selectedGame: IcebreakerChallenge.ChallengeType = .trivia
    /// Captured for the upgrade banner. Display-only — the tier itself is owned
    /// by `MatchManager.submitDemoRating`.
    @State private var tierUpgrade: TierChange?
    @State private var showSafetySheet = false
    @State private var showReport = false

    private struct TierChange {
        let from: UserProfile.TrustLevel
        let to: UserProfile.TrustLevel
    }

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

    private var isIDVerified: Bool {
        partner?.verificationStatus == .verified
    }

    /// Simulated distance, rounded to the nearest 10 m so the label reads calm
    /// rather than twitching every tick.
    private var metersAway: Int {
        max(5, Int((matchManager.demoDistanceMiles * 1609.344 / 10).rounded()) * 10)
    }

    private var proximityLabel: String {
        stage >= .connected ? "Connected · together now" : "\(metersAway) m away · nearby"
    }

    private var safetyCopy: String {
        stage >= .connected
            ? "Report or unmatch anytime · location never shared"
            : "Both must agree to reveal · exit anytime"
    }

    /// Display-only session code (`A7-F3`): first four hex digits of the match
    /// id's unique suffix, uppercased. Never used to look anything up.
    private var sessionCode: String {
        let suffix = (match?.id).map { String($0.split(separator: "_").last ?? "") } ?? ""
        let hex = String(suffix.filter(\.isHexDigit).uppercased().prefix(4))
        let padded = hex.count == 4 ? hex : hex + String(repeating: "0", count: 4 - hex.count)
        return "\(padded.prefix(2))-\(padded.suffix(2))"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack(spacing: DQSpace.block) {
                topBar

                if match == nil || partner == nil {
                    Spacer(); loadingState; Spacer()
                } else if sessionExpired {
                    Spacer(); expiredState; Spacer()
                } else {
                    StageStepper(current: stage)
                    hero
                    panel
                    ctaBlock
                }
            }
            .padding(.top, DQSpace.safeTop)
            .padding(.horizontal, DQSpace.gutter)
            .padding(.bottom, DQSpace.safeBottom)
        }
        // §3's 58pt top padding is measured from the physical top, so the top
        // safe area is absorbed rather than added to. The bottom inset is kept —
        // 22pt alone would put the safety line under the home indicator.
        .ignoresSafeArea(edges: .top)
        .sheet(item: $activeChallenge) { challenge in
            IcebreakerView(challenge: challenge, isDemo: true) {
                matchManager.completeDemoIcebreaker()
                activeChallenge = nil
            }
            .environmentObject(matchManager)
        }
        .sheet(isPresented: $showSafetySheet) {
            SafetySheetView(
                // Ending the encounter is the explicit pass: it re-blurs and
                // frees the encounter slot for both people.
                onEndEncounter: { matchManager.endCurrentEncounter(reason: .pass) },
                onReport: { showReport = true }
            )
        }
        .sheet(isPresented: $showReport) {
            ReportUserView(reportedUID: partner?.uid ?? "")
        }
        // §4: blur, stepper and meter advance together. One gesture, one reward.
        .animation(reduceMotion ? nil : DQMotion.stage, value: stage)
        .animation(reduceMotion ? nil : DQMotion.stage, value: revealProgress)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: DQSpace.tight) {
            DQIconButton(symbol: "xmark", label: "End demo encounter") {
                matchManager.endDemoEncounter()
            }

            Spacer(minLength: 0)

            HStack(spacing: DQSpace.tight) {
                LiveDot()
                Text(proximityLabel)
                    .font(DQFont.labelSized(11))
                    .tracking(DQFont.track(11, em: 0.16))
                    .textCase(.uppercase)
                    .foregroundStyle(p.text2)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // §6.1: the shield ships now that the SafetySheet exists.
            DQIconButton(symbol: "shield", label: "Safety options") {
                showSafetySheet = true
            }

            Menu {
                // Labelled duplicate of the ✕ — a safety-adjacent product never
                // buries the exit.
                Button(role: .destructive) {
                    matchManager.endCurrentEncounter(reason: .pass)
                } label: {
                    Label("End encounter", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis").dqIconChrome()
            }
            .frame(width: DQSize.minHitTarget, height: DQSize.minHitTarget)
            .accessibilityLabel("More options")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        RevealHero(
            name: partner?.displayName ?? "Match",
            age: partner?.age ?? 0,
            progress: revealProgress,
            stage: stage,
            trust: shownTrust,
            isIDVerified: isIDVerified,
            school: partner?.schoolDisplayName,
            sessionCode: sessionCode
        )
    }

    // MARK: - Panel (score at stages 1–3, rating + tier at stage 4)

    @ViewBuilder
    private var panel: some View {
        if stage >= .connected {
            VStack(spacing: 10) {
                ratingCard
                if let upgrade = tierUpgrade {
                    TierUpgradeBanner(from: upgrade.from, to: upgrade.to)
                        .transition(.opacity)
                }
            }
        } else if let breakdown = match?.scoreBreakdown {
            VibeScoreBreakdown(
                overall: match?.compatibilityScore ?? breakdown.overall,
                vibes: partner?.intentVibes ?? [],
                breakdown: breakdown
            )
        }
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Rate your encounter")
                .font(DQFont.labelSized(10))
                .tracking(DQFont.track(10, em: 0.18))
                .textCase(.uppercase)
                .foregroundStyle(p.text2)

            RatingBar(value: demoRating) { star in
                submitRating(star)
            }
        }
        .padding(DQSpace.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .dqShadow(.small(theme))
    }

    /// Unchanged behavior: the real trust-tier rule still runs in
    /// `MatchManager.submitDemoRating`; this only records what to display.
    private func submitRating(_ star: Int) {
        let before = partner?.trustLevel ?? .bronze
        withAnimation(reduceMotion ? nil : DQMotion.press) { demoRating = star }

        let level = matchManager.submitDemoRating(star)

        withAnimation(reduceMotion ? nil : DQMotion.stage) {
            revealedTrust = level
            if level > before { tierUpgrade = TierChange(from: before, to: level) }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - CTA Block

    private var ctaBlock: some View {
        VStack(spacing: DQSpace.tight) {
            if stage == .blurred { gameChooser }
            primaryCTA
            SafetyLine(text: safetyCopy)
        }
    }

    /// Both icebreakers stay reachable without a second tap or an extra pill.
    private var gameChooser: some View {
        HStack(spacing: 7) {
            chooserChip("Trivia", .trivia)
            chooserChip("Word chain", .wordAssociation)
            Spacer(minLength: 0)
        }
    }

    private func chooserChip(_ title: String, _ type: IcebreakerChallenge.ChallengeType) -> some View {
        Button {
            selectedGame = type
        } label: {
            DQChip(text: title, selected: selectedGame == type)
                .frame(minHeight: DQSize.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) icebreaker")
        .accessibilityAddTraits(selectedGame == type ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var primaryCTA: some View {
        switch stage {
        case .blurred:
            // §6.1: while the match is still walking up, the CTA carries the
            // state rather than sitting there dead. `demoReadyForIcebreaker` is
            // MatchManager's gate — unchanged.
            if matchManager.demoReadyForIcebreaker {
                ctaButton {
                    matchManager.startDemoIcebreaker(type: selectedGame)
                    activeChallenge = matchManager.currentIcebreaker
                }
            } else {
                approachPill
            }

        case .partial:
            ctaButton {
                activeChallenge = matchManager.currentIcebreaker
            }
            .disabled(matchManager.currentIcebreaker == nil)

        case .revealed:
            ctaButton {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                matchManager.demoNameDrop()
            }

        case .connected:
            // §6.1 call-site override. `DQReveal.Stage.primaryCTA` returns the
            // shipped copy, "Say hello" — but connected chat is a later pass, so
            // there is nowhere to send anyone yet. "Done" closes the demo loop
            // instead, which keeps the walkthrough runnable back-to-back.
            // Flip this back to `ctaButton` when chat lands.
            ctaButton(title: "Done") {
                matchManager.endDemoEncounter()
            }
        }
    }

    /// Copy and the ember-vs-neutral rule both come from `DQReveal.Stage`,
    /// unless a stage overrides the title (see §6.1, stage 4).
    private func ctaButton(
        title: String? = nil,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(title ?? stage.dq.primaryCTA, action: action)
            .buttonStyle(DQPillButtonStyle(kind: stage.dq.usesEmberCTA ? .ember : .neutral))
    }

    private var approachPill: some View {
        Text("\(metersAway) m away · keep walking")
            .font(DQFont.button)
            .foregroundStyle(p.text2)
            .frame(maxWidth: .infinity)
            .frame(height: DQSize.ghostHeight)
            .overlay(Capsule().strokeBorder(p.lineStrong, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(metersAway) meters away. Keep walking to start an icebreaker.")
    }

    // MARK: - Empty / Error States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(p.ember)
            Text("Finding a match nearby…")
                .font(DQFont.body)
                .foregroundStyle(p.text2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finding a match nearby")
    }

    private var expiredState: some View {
        VStack(spacing: DQSpace.gutter) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(p.text3)

            Text("Encounter window closed")
                .font(DQFont.displayS)
                .tracking(DQFont.trackDisplayS)
                .foregroundStyle(p.text)

            Text("Encounter sessions stay live for 10–15 minutes, then expire to keep things ephemeral and private.")
                .font(DQFont.bodyS)
                .foregroundStyle(p.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Close") { matchManager.endDemoEncounter() }
                .buttonStyle(.dqNeutral)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DQSpace.gutter)
        .accessibilityElement(children: .contain)
    }
}
#endif
