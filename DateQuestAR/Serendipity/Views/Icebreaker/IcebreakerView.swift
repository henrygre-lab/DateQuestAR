import SwiftUI

struct IcebreakerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var matchManager: MatchManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var challenge: IcebreakerChallenge

    @State private var selectedAnswer: String?
    @State private var timeRemaining: Int
    @State private var timer: Timer?
    @State private var isComplete = false
    @State private var celebrationScale: CGFloat = 0.5
    @State private var celebrationOpacity: Double = 0
    @State private var showRating = false
    @State private var showNameDropOverlay = false

    init(challenge: IcebreakerChallenge) {
        self.challenge = challenge
        _timeRemaining = State(initialValue: challenge.durationSeconds)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DQ.Colors.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: DQ.Spacing.huge) {
                    timerRing
                    questionCard
                    if let options = challenge.options {
                        answersGrid(options: options)
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
                        .foregroundStyle(DQ.Colors.textTertiary)
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
        if fraction > 0.5 { return DQ.Colors.accent }
        if fraction > 0.25 { return DQ.Colors.warning }
        return DQ.Colors.error
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(DQ.Colors.surfaceElevated, lineWidth: DQ.Sizing.strokeWidthThick)
                .frame(width: DQ.Sizing.timerRingSize, height: DQ.Sizing.timerRingSize)
            Circle()
                .trim(from: 0, to: CGFloat(timeRemaining) / CGFloat(challenge.durationSeconds))
                .stroke(timerColor, style: StrokeStyle(lineWidth: DQ.Sizing.strokeWidthThick, lineCap: .round))
                .frame(width: DQ.Sizing.timerRingSize, height: DQ.Sizing.timerRingSize)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timeRemaining)
            Text("\(timeRemaining)s")
                .font(DQ.Typography.heroNumber())
                .foregroundStyle(DQ.Colors.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timeRemaining) seconds remaining")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Question Card

    private var questionCard: some View {
        Text(challenge.prompt)
            .font(.title3.bold())
            .foregroundStyle(DQ.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .dqCard(background: DQ.Colors.surfaceCard)
            .accessibilityLabel("Question: \(challenge.prompt)")
    }

    // MARK: - Answers Grid

    private func answersGrid(options: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DQ.Spacing.md) {
            ForEach(options, id: \.self) { option in
                Button {
                    guard selectedAnswer == nil else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectedAnswer = option
                    isComplete = true
                    timer?.invalidate()
                } label: {
                    Text(option)
                        .font(DQ.Typography.body())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DQ.Colors.textPrimary)
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(selectedAnswer == option ? DQ.Colors.accent : DQ.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.large))
                        .overlay(
                            RoundedRectangle(cornerRadius: DQ.Radii.large)
                                .stroke(
                                    selectedAnswer == option ? DQ.Colors.accent : .clear,
                                    lineWidth: 2
                                )
                        )
                        .scaleEffect(selectedAnswer == option ? 1.05 : 1.0)
                        .animation(reduceMotion ? nil : DQ.Anim.spring, value: selectedAnswer)
                }
                .accessibilityHint(selectedAnswer == nil ? "Double tap to select this answer" : "Answer already selected")
            }
        }
    }

    // MARK: - Completion Banner

    private var completionBanner: some View {
        VStack(spacing: DQ.Spacing.lg) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 48))
                .foregroundStyle(DQ.Colors.levelColor)
                .scaleEffect(celebrationScale)
                .opacity(celebrationOpacity)
                .accessibilityHidden(true)

            TrustBadgeView(
                trustLevel: matchManager.nearbyMatchProfile?.trustLevel ?? .bronze,
                size: .medium
            )

            Text("Nice answer!")
                .font(DQ.Typography.sectionHeader())
                .foregroundStyle(DQ.Colors.textPrimary)
            Text("Your match picked too \u{2014} time to exchange info!")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("NameDrop / Exchange Info") {
                initiateNameDrop()
            }
            .buttonStyle(.dqPrimary)
            Button("Rate This Meet") {
                showRating = true
            }
            .foregroundStyle(DQ.Colors.textTertiary)
        }
        .sheet(isPresented: $showRating) {
            PostMeetRatingView(matchID: matchManager.nearbyMatch?.id ?? "")
        }
        .dqCard(background: DQ.Colors.accentSubtle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icebreaker complete! Tap to exchange contact information.")
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
        VStack(spacing: DQ.Spacing.xxl) {
            Spacer()

            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(DQ.Colors.accent)
                .accessibilityHidden(true)

            Text("Exchange Contact Info")
                .font(DQ.Typography.screenTitle())
                .foregroundStyle(DQ.Colors.textPrimary)

            VStack(spacing: DQ.Spacing.lg) {
                instructionStep(number: 1, text: "Hold the top of your iPhone close to the top of your match's iPhone.")
                instructionStep(number: 2, text: "A NameDrop prompt will appear on both screens.")
                instructionStep(number: 3, text: "Choose which contact info to share, then tap Share.")
            }
            .padding(.horizontal, DQ.Spacing.lg)

            Text("Both devices must be unlocked with iOS 17 or later.")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.textQuaternary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Got It") {
                dismiss()
            }
            .buttonStyle(.dqPrimary)
            .padding(.horizontal, DQ.Spacing.xl)
        }
        .padding(DQ.Spacing.xl)
        .dqBackground(heroGlow: true)
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: DQ.Spacing.md) {
            Text("\(number)")
                .font(DQ.Typography.bodyBold())
                .foregroundStyle(DQ.Colors.accent)
                .frame(width: 28, height: 28)
                .background(DQ.Colors.accent.opacity(0.15))
                .clipShape(Circle())

            Text(text)
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
