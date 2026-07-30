import SwiftUI

/// Shared AR icebreaker challenge. Supports Trivia (single pick) and Word
/// Association (a short chain), plus lighter Gesture / AR Object types.
///
/// DesignSystem v2 skin (docs/DESIGN_SYSTEM.md §5, §6 row 2): top bar →
/// persistent partner strip → progress row → game card → feedback banner →
/// CTA. All challenge logic, the word-chain rounds, the timer and the demo
/// completion hand-off are unchanged; only the presentation moved.
struct IcebreakerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var matchManager: MatchManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme
    @ObservedObject private var revealManager = RevealManager.shared
    var challenge: IcebreakerChallenge

    /// When true, completion hands control back to the demo walkthrough
    /// (`onFinished`) instead of showing the production NameDrop overlay.
    var isDemo: Bool = false
    var onFinished: (() -> Void)?

    @State private var selectedAnswer: String?
    @State private var timeRemaining: Int
    @State private var timer: Timer?
    @State private var isComplete = false
    @State private var showRating = false
    @State private var showNameDropOverlay = false

    // Word Association chain state
    @State private var round = 1
    @State private var chainPrompt = ""
    private let wordChainRounds = 3

    /// Display-only record of the links played so far, so the chain can be
    /// drawn as pills. The game itself still advances on `round`/`chainPrompt`.
    @State private var chainHistory: [String] = []

    @State private var feedback: String?
    @State private var feedbackKind: FeedbackBanner.Kind = .success

    init(challenge: IcebreakerChallenge, isDemo: Bool = false, onFinished: (() -> Void)? = nil) {
        self.challenge = challenge
        self.isDemo = isDemo
        self.onFinished = onFinished
        _timeRemaining = State(initialValue: challenge.durationSeconds)
        _chainPrompt = State(initialValue: challenge.prompt)
    }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack(spacing: DQSpace.block) {
                topBar
                if let partner = matchManager.nearbyMatchProfile {
                    PartnerStrip(
                        name: partner.displayName,
                        progress: revealProgress,
                        tier: partner.trustLevel
                    )
                }
                progressRow
                gameCard
                if let feedback {
                    FeedbackBanner(text: feedback, kind: feedbackKind)
                        .transition(.opacity)
                }
                ctaBlock
            }
            // §3's 58 clears a status bar. Inside a sheet there isn't one, so
            // the gutter is the right breathing room off the sheet's own edge.
            .padding(.top, DQSpace.gutter)
            .padding(.horizontal, DQSpace.gutter)
            .padding(.bottom, DQSpace.safeBottom)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .sheet(isPresented: $showNameDropOverlay) {
            NameDropInstructionView()
        }
        .sheet(isPresented: $showRating) {
            PostMeetRatingView(matchID: matchManager.nearbyMatch?.id ?? "")
        }
        .animation(reduceMotion ? nil : DQMotion.stage, value: revealProgress)
        .animation(reduceMotion ? nil : DQMotion.stage, value: round)
        .animation(reduceMotion ? nil : DQMotion.stage, value: isComplete)
    }

    // MARK: - Derived

    private var revealProgress: Double {
        matchManager.nearbyMatch
            .flatMap { revealManager.activeSessions[$0.id]?.revealProgress } ?? 0.0
    }

    private var isWordChain: Bool { challenge.type == .wordAssociation }

    private var gameTitle: String {
        switch challenge.type {
        case .trivia:          "Trivia"
        case .wordAssociation: "Word chain"
        case .gesture:         "Gesture"
        case .arObject:        "AR object"
        }
    }

    /// The chain as drawn: the seed the partner played, then each of your
    /// links, then — while play continues — the word currently open for
    /// linking. Once complete there is no open slot; every word has been played.
    ///
    /// The demo chain is one-sided: only the seed is the partner's, because the
    /// game takes no partner input. The mock alternates theirs/yours since it
    /// depicts a real two-player chain.
    private var chainLinks: [(word: String, owner: WordChainPill.Owner)] {
        var links: [(String, WordChainPill.Owner)] = []
        for (index, word) in chainHistory.enumerated() {
            links.append((word, index == 0 ? .theirs : .yours))
        }
        if !isComplete { links.append((chainPrompt, .open)) }
        return links
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: DQSpace.tight) {
            DQIconButton(symbol: "chevron.left", label: "Skip icebreaker") { dismiss() }

            Spacer(minLength: 0)

            Text(gameTitle)
                .font(DQFont.labelSized(11))
                .tracking(DQFont.track(11, em: 0.18))
                .textCase(.uppercase)
                .foregroundStyle(p.text2)

            Spacer(minLength: 0)

            Menu {
                Button(role: .cancel) { dismiss() } label: {
                    Label("Skip icebreaker", systemImage: "forward.end")
                }
            } label: {
                Image(systemName: "ellipsis").dqIconChrome()
            }
            .frame(width: DQSize.minHitTarget, height: DQSize.minHitTarget)
            .accessibilityLabel("More options")
        }
    }

    // MARK: - Progress Row

    private var progressRow: some View {
        HStack(spacing: DQSpace.tight) {
            Text("\(timeRemaining)s left")
                .font(DQFont.labelSized(10, .semibold))
                .tracking(DQFont.track(10, em: 0.14))
                .textCase(.uppercase)
                .foregroundStyle(timeRemaining <= challenge.durationSeconds / 4
                                 ? p.text : p.text2)
                .monospacedDigit()
                .accessibilityLabel("\(timeRemaining) seconds remaining")
                .accessibilityAddTraits(.updatesFrequently)

            Spacer(minLength: 0)

            if isWordChain {
                ProgressPips(total: wordChainRounds, filled: min(round - 1, wordChainRounds))
            }
        }
    }

    // MARK: - Game Card

    @ViewBuilder
    private var gameCard: some View {
        Group {
            if isWordChain {
                wordChainCard
            } else if let options = challenge.options {
                triviaCard(options: options)
            } else {
                gestureCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous)
                .fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .dqShadow(.small(theme))
    }

    private func triviaCard(options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            eyebrow("Mutual prompt")

            Text(challenge.prompt)
                .font(DQFont.title)
                .tracking(DQFont.trackTitle)
                .foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DQSpace.tight) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    IcebreakerOptionRow(
                        text: option,
                        letter: Self.optionLetters[index % Self.optionLetters.count],
                        isSelected: selectedAnswer == option,
                        isEnabled: selectedAnswer == nil && !isComplete
                    ) {
                        handleSelection(option)
                    }
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
    }

    private var wordChainCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            eyebrow("Shared chain")

            // §5's streak chip has no backing data on IcebreakerChallenge, so
            // it is omitted rather than invented — same rule §5 applies to the
            // VibeScoreBreakdown percentile.
            FlowLayout(spacing: 8) {
                ForEach(Array(chainLinks.enumerated()), id: \.offset) { _, link in
                    WordChainPill(word: link.word, owner: link.owner)
                }
            }

            if let options = challenge.options, !isComplete {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Link a word to \u{201C}\(chainPrompt)\u{201D}")
                        .font(DQFont.labelSized(9, .semibold))
                        .tracking(DQFont.track(9, em: 0.16))
                        .textCase(.uppercase)
                        .foregroundStyle(p.text2)

                    // §5 specifies a free-text input with an ember send FAB.
                    // The chain advances by picking from `challenge.options` —
                    // accepting arbitrary words is a new game rule, not a skin,
                    // so the option rows stay until that logic exists.
                    VStack(spacing: DQSpace.tight) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            IcebreakerOptionRow(
                                text: option,
                                letter: Self.optionLetters[index % Self.optionLetters.count],
                                isSelected: selectedAnswer == option,
                                isEnabled: selectedAnswer == nil
                            ) {
                                handleSelection(option)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }

    private var gestureCard: some View {
        VStack(spacing: DQSpace.gutter) {
            Spacer(minLength: 0)
            Image(systemName: challenge.type == .arObject ? "cube.transparent" : "hand.wave")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(p.text2)
            Text(challenge.prompt)
                .font(DQFont.titleS)
                .tracking(DQFont.trackTitleS)
                .foregroundStyle(p.text)
                .multilineTextAlignment(.center)
            Button("Done") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                complete(feedback: "Nice one")
            }
            .buttonStyle(.dqNeutral)
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(DQFont.labelSized(9, .semibold))
            .tracking(DQFont.track(9, em: 0.2))
            .textCase(.uppercase)
            .foregroundStyle(p.text3)
    }

    // MARK: - CTA

    @ViewBuilder
    private var ctaBlock: some View {
        if isComplete {
            if isDemo {
                Button("Continue") { onFinished?() }
                    .buttonStyle(.dqNeutral)
            } else {
                VStack(spacing: DQSpace.tight) {
                    Button("NameDrop / Exchange Info") { initiateNameDrop() }
                        .buttonStyle(.dqNeutral)
                    Button("Rate this meet") { showRating = true }
                        .buttonStyle(.dqGhost)
                }
            }
        } else {
            // A disabled pill is a dead end (§6.1); this one reports what the
            // screen is waiting for instead.
            Text(isWordChain ? "Choose a link" : "Pick an answer")
                .font(DQFont.button)
                .foregroundStyle(p.text2)
                .frame(maxWidth: .infinity)
                .frame(height: DQSize.ghostHeight)
                .overlay(Capsule().strokeBorder(p.lineStrong, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Selection

    private func handleSelection(_ option: String) {
        guard selectedAnswer == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Word Association: chain forward for a few rounds before finishing.
        if challenge.type == .wordAssociation && round < wordChainRounds {
            withAnimation(reduceMotion ? nil : DQMotion.stage) {
                chainHistory.append(chainPrompt)
                round += 1
                chainPrompt = option
                feedback = "Strong link"
                feedbackKind = .success
            }
            return
        }

        selectedAnswer = option
        if challenge.type == .wordAssociation {
            // Close the chain out: the word that was open, then the final link.
            chainHistory.append(chainPrompt)
            chainHistory.append(option)
        }
        complete(feedback: isWordChain ? "Chain complete" : "Answer locked in")
    }

    private func complete(feedback text: String) {
        timer?.invalidate()
        withAnimation(reduceMotion ? nil : DQMotion.stage) {
            feedback = text
            feedbackKind = .success
            isComplete = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Helpers

    private static let optionLetters = ["A", "B", "C", "D"]

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
                // VoiceOver announcements at key intervals
                if timeRemaining == 20 || timeRemaining == 10 || timeRemaining == 5 {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "\(timeRemaining) seconds remaining"
                    )
                }
                if timeRemaining == 0 {
                    UIAccessibility.post(notification: .announcement, argument: "Time is up")
                }
            } else {
                timer?.invalidate()
                withAnimation(reduceMotion ? nil : DQMotion.stage) {
                    feedback = "Time's up"
                    feedbackKind = .neutral
                    isComplete = true
                }
            }
        }
    }

    private func initiateNameDrop() {
        showNameDropOverlay = true
    }
}
