import SwiftUI

struct PostMeetRatingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var matchManager: MatchManager

    let matchID: String

    @State private var photoAccuracyRating: Int = 0
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DQ.Spacing.xxl) {
                Spacer()

                // Header
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(DQ.Colors.accent)

                Text("Rate Your Meet")
                    .font(DQ.Typography.sectionHeader())
                    .foregroundStyle(DQ.Colors.textPrimary)

                // Question
                VStack(spacing: DQ.Spacing.lg) {
                    Text("Did they look like their photos?")
                        .font(DQ.Typography.body())
                        .foregroundStyle(DQ.Colors.textSecondary)

                    // Star rating
                    HStack(spacing: DQ.Spacing.md) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                withAnimation(DQ.Anim.quick) {
                                    photoAccuracyRating = star
                                }
                            } label: {
                                Image(systemName: star <= photoAccuracyRating ? "star.fill" : "star")
                                    .font(.system(size: 36))
                                    .foregroundStyle(
                                        star <= photoAccuracyRating
                                            ? DQ.Colors.levelColor
                                            : DQ.Colors.textQuaternary
                                    )
                            }
                            .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                        }
                    }

                    // Rating label
                    if photoAccuracyRating > 0 {
                        Text(ratingLabel)
                            .font(DQ.Typography.caption())
                            .foregroundStyle(DQ.Colors.textTertiary)
                            .transition(.opacity)
                    }
                }
                .dqCard(background: DQ.Colors.surfaceCard)

                Spacer()

                // Submit
                if submitted {
                    Label("Thanks for your feedback!", systemImage: "checkmark.circle.fill")
                        .font(DQ.Typography.bodyBold())
                        .foregroundStyle(DQ.Colors.success)
                } else {
                    Button {
                        submitRating()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(DQ.Colors.textPrimary)
                        } else {
                            Text("Submit")
                        }
                    }
                    .buttonStyle(.dqPrimary)
                    .disabled(photoAccuracyRating == 0 || isSubmitting)
                    .opacity(photoAccuracyRating == 0 ? 0.5 : 1.0)
                }

                Button("Skip") {
                    dismiss()
                }
                .foregroundStyle(DQ.Colors.textTertiary)
                .padding(.bottom, DQ.Spacing.lg)
            }
            .padding(.horizontal, DQ.Spacing.xxl)
            .dqBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Helpers

    private var ratingLabel: String {
        switch photoAccuracyRating {
        case 1: "Not at all"
        case 2: "Somewhat different"
        case 3: "Mostly accurate"
        case 4: "Very accurate"
        case 5: "Spot on!"
        default: ""
        }
    }

    private func submitRating() {
        isSubmitting = true
        Task {
            await matchManager.submitPhotoAccuracyRating(
                matchID: matchID,
                rating: photoAccuracyRating
            )
            isSubmitting = false
            submitted = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        }
    }
}
