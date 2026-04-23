import SwiftUI

struct StatsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DQ.Spacing.xxl) {
                    statsGrid
                }
                .padding(.horizontal, DQ.Spacing.xl)
                .padding(.top, DQ.Spacing.lg)
                .padding(.bottom, DQ.Spacing.huge)
            }
            .dqBackground(heroGlow: false)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your Stats")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DQ.Colors.textPrimary)
                }
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let gam = authViewModel.currentUser?.gamification
        let verified = authViewModel.currentUser?.verificationStatus == .verified

        return VStack(spacing: DQ.Spacing.md) {
            HStack(spacing: DQ.Spacing.md) {
                StatBadge(icon: "star.fill", value: "\(gam?.computedLevel ?? 1)", label: "Level", color: DQ.Colors.levelColor)
                StatBadge(icon: "bolt.fill", value: "\(gam?.totalXP ?? 0)", label: "XP", color: DQ.Colors.xpColor)
                StatBadge(icon: "flame.fill", value: "\(gam?.currentStreakDays ?? 0)", label: "Streak", color: DQ.Colors.questColor)
            }

            HStack(spacing: DQ.Spacing.md) {
                StatBadge(
                    icon: "checkmark.seal.fill",
                    value: verified ? "Yes" : "No",
                    label: "Verified",
                    color: verified ? DQ.Colors.success : DQ.Colors.textQuaternary
                )
            }
        }
    }
}
