import SwiftUI

/// Shared AR icebreaker challenge. Supports Trivia (single pick) and Word
/// Association (a short chain), plus lighter Gesture / AR Object types.
///
/// Visual rebuild: dark-only, high-contrast mono surfaces with a single signal
/// accent. All challenge logic, the word-chain rounds, the demo completion
/// hand-off, and the partner reveal thumbnail are unchanged.
struct IcebreakerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var matchManager: MatchManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var celebrationScale: CGFloat = 0.5
    @State private var celebrationOpacity: Double = 0
    @State private var showRating = false
    @State private var showNameDropOverlay = false

    // Word Association chain state
    @State private var round = 1
    @State private var chainPrompt = ""
    private let wordChainRounds = 3

    init(challenge: IcebreakerChallenge, isDemo: Bool = false, onFinished: (() -> Void)? = nil) {
        self.challenge = challenge
        self.isDemo = isDemo
        self.onFinished = onFinished
        _timeRemaining = State(initialValue: challenge.durationSeconds)
        _chainPrompt = State(initialValue: challenge.prompt)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DQ.Colors.mono0.ignoresSafeArea()
                VStack(spacing: DQ.Spacing.xl) {
                    if isDemo { partnerRevealThumb }
                    timerRing
                    questionCard
                    if !isComplete {
                        if let options = challenge.options {
                            answersGrid(options: options)
                        } else {
                            gestureCard
                        }
                    }
                    if isComplete { completionBanner }
                }
                .padding()
            }
            .navigationTitle("Icebreaker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(DQ.Colors.mono600)
                        .accessibilityLabel("Skip icebreaker")
                }
            }
            .onAppear { startTimer() }
            .onDisappear { timer?.invalidate() }
            .sheet(isPresented: $showNameDropOverlay) {
                NameDropInstructionView()
            }
        }
    }

    // MARK: - Timer Ring

    private var timerColor: Color {
        let fraction = Double(timeRemaining) / Double(challenge.durationSeconds)
        if fraction > 0.5 { return DQ.Colors.signal }
        if fraction > 0.25 { return DQ.Colors.warning }
        return DQ.Colors.danger
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(DQ.Colors.mono300, lineWidth: DQ.Sizing.strokeWidthThick)
                .frame(width: DQ.Sizing.timerRingSize, height: DQ.Sizing.timerRingSize)
            Circle()
                .trim(from: 0, to: CGFloat(timeRemaining) / CGFloat(challenge.durationSeconds))
                .stroke(timerColor, style: StrokeStyle(lineWidth: DQ.Sizing.strokeWidthThick, lineCap: .round))
                .frame(width: DQ.Sizing.timerRingSize, height: DQ.Sizing.timerRingSize)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timeRemaining)
            Text("\(timeRemaining)")
                .font(DQ.Typography.mono(26, weight: .bold))
                .foregroundStyle(DQ.Colors.mono900)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timeRemaining) seconds remaining")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Question Card

    private var questionCard: some View {
        VStack(spacing: DQ.Spacing.xs) {
            if challenge.type == .wordAssociation {
                Text("WORD CHAIN · ROUND \(min(round, wordChainRounds))/\(wordChainRounds)")
                    .font(DQ.Typography.mono(10, weight: .semibold))
                    .foregroundStyle(DQ.Colors.signal)
            }
            Text(displayPrompt)
                .font(.title3.bold())
                .foregroundStyle(DQ.Colors.mono900)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DQ.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: DQ.Radii.xl).fill(DQ.Colors.mono100))
        .overlay(RoundedRectangle(cornerRadius: DQ.Radii.xl).stroke(DQ.Colors.mono300, lineWidth: 1))
        .accessibilityLabel("Prompt: \(displayPrompt)")
    }

    private var displayPrompt: String {
        if challenge.type == .wordAssociation {
            return "\(chainPrompt)  →  ?"
        }
        return challenge.prompt
    }

    // MARK: - Partner Reveal Thumb (demo)

    /// A small avatar that unblurs in real time as the shared reveal progresses,
    /// making the "progressive unblur during the icebreaker" contract visible
    /// while the challenge is on screen.
    private var partnerRevealThumb: some View {
        let progress = matchManager.nearbyMatch.flatMap { revealManager.activeSessions[$0.id]?.revealProgress } ?? 0.0
        return HStack(spacing: DQ.Spacing.sm) {
            Circle()
                .fill(LinearGradient(colors: [DQ.Colors.mono400, DQ.Colors.mono200],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
                .blur(radius: CGFloat(1.0 - progress) * 12)
                .clipShape(Circle())
                .overlay(Circle().stroke(DQ.Colors.mono300, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text("Revealing your match")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.mono800)
                Text("\(Int(progress * 100))% clear")
                    .font(DQ.Typography.mono(10, weight: .medium))
                    .foregroundStyle(DQ.Colors.mono600)
            }
            Spacer()
        }
        .padding(DQ.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DQ.Radii.medium).fill(DQ.Colors.mono100))
        .overlay(RoundedRectangle(cornerRadius: DQ.Radii.medium).stroke(DQ.Colors.mono300, lineWidth: 1))
        .accessibilityLabel("Match photo \(Int(progress * 100)) percent revealed")
    }

    // MARK: - Gesture / AR Object Card (lighter challenge types)

    private var gestureCard: some View {
        VStack(spacing: DQ.Spacing.lg) {
            Image(systemName: challenge.type == .arObject ? "cube.transparent" : "hand.wave")
                .font(.system(size: 44))
                .foregroundStyle(DQ.Colors.signal)
            Button("Done") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isComplete = true
                timer?.invalidate()
            }
            .buttonStyle(.dqSignal)
        }
        .frame(maxWidth: .infinity)
        .padding(DQ.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: DQ.Radii.xl).fill(DQ.Colors.mono100))
        .overlay(RoundedRectangle(cornerRadius: DQ.Radii.xl).stroke(DQ.Colors.mono300, lineWidth: 1))
    }

    // MARK: - Answers Grid

    private func answersGrid(options: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DQ.Spacing.md) {
            ForEach(options, id: \.self) { option in
                let isSelected = selectedAnswer == option
                Button {
                    handleSelection(option)
                } label: {
                    Text(option)
                        .font(DQ.Typography.body())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isSelected ? DQ.Colors.mono0 : DQ.Colors.mono900)
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(isSelected ? DQ.Colors.signal : DQ.Colors.mono100)
                        .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.large))
                        .overlay(
                            RoundedRectangle(cornerRadius: DQ.Radii.large)
                                .stroke(isSelected ? DQ.Colors.signal : DQ.Colors.mono300, lineWidth: 1)
                        )
                        .scaleEffect(isSelected ? 1.04 : 1.0)
                        .animation(reduceMotion ? nil : DQ.Anim.spring, value: selectedAnswer)
                }
                .accessibilityHint(selectedAnswer == nil ? "Double tap to select this answer" : "Answer already selected")
            }
        }
    }

    // MARK: - Completion Banner

    private var completionBanner: some View {
        VStack(spacing: DQ.Spacing.lg) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(DQ.Colors.signal)
                .scaleEffect(celebrationScale)
                .opacity(celebrationOpacity)
                .accessibilityHidden(true)

            TrustBadgeView(
                trustLevel: matchManager.nearbyMatchProfile?.trustLevel ?? .bronze,
                size: .medium
            )

            Text("Nice answer")
                .font(DQ.Typography.sectionHeader())
                .foregroundStyle(DQ.Colors.mono900)
            Text("Your match picked too \u{2014} time to exchange info.")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.mono700)
                .multilineTextAlignment(.center)
            if isDemo {
                Button("Continue") {
                    onFinished?()
                }
                .buttonStyle(.dqSignal)
            } else {
                Button("NameDrop / Exchange Info") {
                    initiateNameDrop()
                }
                .buttonStyle(.dqSignal)
                Button("Rate this meet") {
                    showRating = true
                }
                .foregroundStyle(DQ.Colors.mono600)
            }
        }
        .sheet(isPresented: $showRating) {
            PostMeetRatingView(matchID: matchManager.nearbyMatch?.id ?? "")
        }
        .frame(maxWidth: .infinity)
        .padding(DQ.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: DQ.Radii.xl).fill(DQ.Colors.mono100))
        .overlay(RoundedRectangle(cornerRadius: DQ.Radii.xl).stroke(DQ.Colors.mono300, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icebreaker complete. Tap to exchange contact information.")
        .onAppear {
            guard !reduceMotion else {
                celebrationScale = 1.0
                celebrationOpacity = 1.0
                return
            }
            withAnimation(DQ.Anim.bouncy) {
                celebrationScale = 1.0
                celebrationOpacity = 1.0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Selection

    private func handleSelection(_ option: String) {
        guard selectedAnswer == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Word Association: chain forward for a few rounds before finishing.
        if challenge.type == .wordAssociation && round < wordChainRounds {
            withAnimation(reduceMotion ? nil : DQ.Anim.spring) {
                round += 1
                chainPrompt = option
            }
            return
        }

        selectedAnswer = option
        isComplete = true
        timer?.invalidate()
    }

    // MARK: - Helpers

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
                isComplete = true
            }
        }
    }

    private func initiateNameDrop() {
        showNameDropOverlay = true
    }
}

// MARK: - NameDrop Instruction View

struct NameDropInstructionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DQ.Colors.mono0.ignoresSafeArea()
            VStack(spacing: DQ.Spacing.xxl) {
                Spacer()

                Image(systemName: "wave.3.right")
                    .font(.system(size: 60))
                    .foregroundStyle(DQ.Colors.signal)
                    .accessibilityHidden(true)

                Text("Exchange contact info")
                    .font(DQ.Typography.screenTitle())
                    .foregroundStyle(DQ.Colors.mono900)

                VStack(spacing: DQ.Spacing.lg) {
                    instructionStep(number: 1, text: "Hold the top of your iPhone close to the top of your match's iPhone.")
                    instructionStep(number: 2, text: "A NameDrop prompt will appear on both screens.")
                    instructionStep(number: 3, text: "Choose which contact info to share, then tap Share.")
                }
                .padding(.horizontal, DQ.Spacing.lg)

                Text("Both devices must be unlocked with iOS 17 or later.")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.mono600)
                    .multilineTextAlignment(.center)

                Spacer()

                Button("Got it") {
                    dismiss()
                }
                .buttonStyle(.dqSignal)
                .padding(.horizontal, DQ.Spacing.xl)
            }
            .padding(DQ.Spacing.xl)
        }
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: DQ.Spacing.md) {
            Text("\(number)")
                .font(DQ.Typography.bodyBold())
                .foregroundStyle(DQ.Colors.signal)
                .frame(width: 28, height: 28)
                .background(DQ.Colors.signalSubtle)
                .clipShape(Circle())

            Text(text)
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.mono700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
