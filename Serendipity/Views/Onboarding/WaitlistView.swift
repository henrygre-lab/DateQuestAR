// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Waitlist status read from Firestore (read-only on client)
// [x] Activation managed server-side by Cloud Functions — client polls only
// [x] No PII displayed — only wait time estimate and status
// [x] accountStatus transition to .active triggers navigation to HomeView
// [x] Referral link generation would use server-side function (stubbed for Phase 5)

import SwiftUI
import FirebaseFirestore

struct WaitlistView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var balanceEnforcer: BalanceEnforcer

    @State private var estimatedHours: Int = 24
    @State private var elapsedFraction: Double = 0.0
    @State private var isChecking = false
    @State private var ringPulse = false

    var body: some View {
        VStack(spacing: DQ.Spacing.huge) {
            Spacer()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(DQ.Colors.surfaceElevated, lineWidth: 8)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: elapsedFraction)
                    .stroke(
                        AngularGradient(
                            colors: [DQ.Colors.accent, DQ.Colors.accentPink, DQ.Colors.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: DQ.Spacing.xxs) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(DQ.Colors.accent)
                    Text(remainingTimeText)
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                }
            }
            .scaleEffect(ringPulse ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: ringPulse)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Estimated wait: \(remainingTimeText)")

            // Status text
            VStack(spacing: DQ.Spacing.md) {
                Text("You're on the Waitlist")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DQ.Colors.textPrimary)

                Text("To keep Serendipity balanced and safe for everyone, we're managing the number of new accounts. You'll be activated soon!")
                    .font(DQ.Typography.body())
                    .foregroundStyle(DQ.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DQ.Spacing.xl)
            }

            // Referral nudge
            VStack(spacing: DQ.Spacing.md) {
                HStack(spacing: DQ.Spacing.sm) {
                    Image(systemName: "gift.fill")
                        .foregroundStyle(DQ.Colors.accentPink)
                    Text("Skip the line!")
                        .font(DQ.Typography.bodyBold())
                        .foregroundStyle(DQ.Colors.textPrimary)
                }

                Text("Invite friends to move up. Each friend who joins boosts your priority.")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.textTertiary)
                    .multilineTextAlignment(.center)

                Button {
                    shareReferralLink()
                } label: {
                    Label("Invite Friends", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dqSecondary)
                .padding(.horizontal, DQ.Spacing.huge)
            }
            .padding(DQ.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: DQ.Radii.xl)
                    .fill(DQ.Colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DQ.Radii.xl)
                            .stroke(DQ.Colors.accentPink.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, DQ.Spacing.xl)

            Spacer()

            // Check status button
            Button {
                Task { await checkStatus() }
            } label: {
                if isChecking {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Check Status")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.dqPrimary)
            .disabled(isChecking)
            .padding(.horizontal, DQ.Spacing.xl)
            .padding(.bottom, DQ.Spacing.giant)
        }
        .dqBackground(heroGlow: true)
        .onAppear {
            ringPulse = true
            Task { await loadWaitlistInfo() }
        }
    }

    // MARK: - Remaining Time

    private var remainingTimeText: String {
        let remaining = max(0, estimatedHours - Int(elapsedFraction * Double(estimatedHours)))
        if remaining <= 0 { return "Soon!" }
        if remaining == 1 { return "~1 hour" }
        return "~\(remaining) hrs"
    }

    // MARK: - Load Waitlist Info

    private func loadWaitlistInfo() async {
        guard let uid = authViewModel.currentUser?.uid else { return }
        do {
            if let entry = try await FirestoreService.shared.fetchWaitlistEntry(uid: uid) {
                let entryDate = entry.entryTime.dateValue()
                let totalHours = Double(authViewModel.currentUser?.activationDelayHours ?? 24)
                let elapsed = Date().timeIntervalSince(entryDate) / 3600.0
                await MainActor.run {
                    estimatedHours = Int(totalHours)
                    elapsedFraction = min(1.0, elapsed / totalHours)
                }
            }
        } catch {
            Log.waitlist.error("Failed to load waitlist info: \(error.localizedDescription)")
        }
    }

    // MARK: - Check Status

    private func checkStatus() async {
        guard let uid = authViewModel.currentUser?.uid else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let status = try await FirestoreService.shared.fetchAccountStatus(uid: uid)
            if status == .active {
                await MainActor.run {
                    authViewModel.appState = .authenticated
                }
            }
        } catch {
            Log.waitlist.error("Status check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Referral

    private func shareReferralLink() {
        // TODO: Phase 5 — generate referral link via Cloud Function
        let text = "Join me on Serendipity — a dating app where you actually meet in person!"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(activityVC, animated: true)
    }
}
