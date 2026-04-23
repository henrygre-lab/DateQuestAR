import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var matchManager: MatchManager
    @EnvironmentObject var locationService: LocationService
    @State private var selectedTab: Tab = .home
    @State private var showRadar = false
    @State private var scanPulse = false
    @State private var questCardBounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tab { case home, stats, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
                .tabItem { Label("Quest", systemImage: "location.north.circle.fill") }
                .tag(Tab.home)

            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(Tab.stats)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(DQ.Colors.accent)
        .fullScreenCover(isPresented: $showRadar) {
            RadarView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .matchAlertTapped)) { _ in
            showRadar = true
        }
    }

    // MARK: - Dashboard Tab

    private var dashboardTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DQ.Spacing.xxl) {
                    greetingHeader
                    HomeRadarPreview(
                        isActive: matchManager.isQuestModeActive,
                        nearbyCount: matchManager.activeMatches.count
                    )
                    questModeCard
                    if !matchManager.activeMatches.isEmpty { nearbyMatchBanner }
                }
                .padding(.horizontal, DQ.Spacing.xl)
                .padding(.bottom, DQ.Spacing.huge)
            }
            .dqBackground(heroGlow: true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Serendipity")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DQ.Colors.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { authViewModel.signOut() } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DQ.Colors.textQuaternary)
                    }
                    .accessibilityLabel("Sign out")
                }
            }
        }
    }

    // MARK: - Greeting Header (centered large avatar + text below)

    private var greetingHeader: some View {
        let name = authViewModel.currentUser?.displayName ?? "Quester"
        let questActive = matchManager.isQuestModeActive

        return VStack(spacing: DQ.Spacing.lg) {
            // Large centered avatar — fixed 110pt with 4pt ring
            ZStack {
                // Gradient placeholder with initials
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DQ.Colors.accentPink, DQ.Colors.accent],
                            center: .center, startRadius: 10, endRadius: 60
                        )
                    )
                    .frame(width: 110, height: 110)
                    .overlay(
                        Text(initials(from: name))
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white)
                    )

                // Purple ring stroke
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [DQ.Colors.accent, DQ.Colors.accentPink],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 118, height: 118)

                // Online indicator when quest mode active
                if questActive {
                    Circle()
                        .fill(DQ.Colors.success)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(DQ.Colors.backgroundPrimary, lineWidth: 3))
                        .offset(x: 46, y: 46)
                }
            }
            .frame(width: 118, height: 118)
            .shadow(
                color: questActive ? .purple.opacity(0.4) : .clear,
                radius: questActive ? 12 : 0
            )
            .accessibilityHidden(true)

            // Greeting text centered below avatar
            VStack(spacing: DQ.Spacing.xxs) {
                Text("Hey, \(name)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(DQ.Colors.textPrimary)
                Text(questActive ? "Quest Mode Active" : "Quest Mode Off")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(questActive ? DQ.Colors.success : DQ.Colors.textQuaternary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hey \(name). Quest Mode is \(questActive ? "active" : "off")")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, DQ.Spacing.huge)
        .padding(.bottom, DQ.Spacing.xxl)
    }

    // MARK: - Quest Mode Card

    private var questModeCard: some View {
        let questActive = matchManager.isQuestModeActive

        return VStack(spacing: DQ.Spacing.xl) {
            HStack(alignment: .top, spacing: DQ.Spacing.md) {
                VStack(alignment: .leading, spacing: DQ.Spacing.xs) {
                    Text("Quest Mode")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Text("Scan nearby for compatible matches within 0.25 mi")
                        .font(DQ.Typography.caption())
                        .foregroundStyle(DQ.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { matchManager.isQuestModeActive },
                    set: { active in
                        if active, let user = authViewModel.currentUser {
                            matchManager.enableQuestMode(for: user)
                        } else {
                            matchManager.disableQuestMode()
                        }
                        // Micro-bounce on toggle
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            questCardBounce = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            questCardBounce = false
                        }
                    }
                ))
                .labelsHidden()
                .tint(DQ.Colors.accent)
                .scaleEffect(1.1)
                .fixedSize()
                .accessibilityLabel("Quest Mode")
                .accessibilityHint("Double tap to toggle quest scanning")
            }

            // Dynamic status text
            Text(questActive ? "Scanning… 0.25 mi radius" : "Ready to scan nearby matches")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(questActive ? DQ.Colors.textSecondary : DQ.Colors.textQuaternary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.3), value: questActive)

            if questActive {
                HStack(spacing: DQ.Spacing.xs) {
                    Circle()
                        .fill(DQ.Colors.success)
                        .frame(width: 8, height: 8)
                        .opacity(scanPulse ? 1.0 : 0.4)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: scanPulse
                        )
                    Text("Scanning")
                        .font(DQ.Typography.caption())
                        .foregroundStyle(DQ.Colors.success)
                    Spacer()
                    Text("\(matchManager.activeMatches.count) nearby")
                        .font(DQ.Typography.caption())
                        .foregroundStyle(DQ.Colors.textQuaternary)
                        .padding(.horizontal, DQ.Spacing.sm)
                        .padding(.vertical, DQ.Spacing.xxxs)
                        .background(DQ.Colors.surfaceElevated)
                        .clipShape(Capsule())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Scanning. \(matchManager.activeMatches.count) potential matches nearby.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DQ.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: DQ.Radii.xl)
                .fill(DQ.Colors.surfaceCard)
                .overlay(
                    // Radial purple glow when quest mode is ON
                    Group {
                        if questActive {
                            RoundedRectangle(cornerRadius: DQ.Radii.xl)
                                .fill(
                                    RadialGradient(
                                        colors: [DQ.Colors.accent.opacity(0.3), .clear],
                                        center: .center, startRadius: 0, endRadius: 200
                                    )
                                )
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DQ.Radii.xl)
                        .stroke(
                            questActive
                                ? DQ.Colors.accent.opacity(0.4)
                                : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: questActive ? DQ.Shadows.glow : .clear,
            radius: questActive ? DQ.Shadows.glowRadius : 0
        )
        .scaleEffect(questCardBounce ? 1.03 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: questCardBounce)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: questActive)
        .onAppear { scanPulse = true }
    }

    // MARK: - Nearby Match Banner

    private var nearbyMatchBanner: some View {
        Button { showRadar = true } label: {
            HStack(spacing: DQ.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DQ.Colors.accentOrange.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DQ.Colors.accentOrange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DQ.Spacing.xs) {
                        Text("Match Nearby!")
                            .font(DQ.Typography.bodyBold())
                            .foregroundStyle(DQ.Colors.textPrimary)
                        TrustBadgeView(
                            trustLevel: matchManager.nearbyMatchProfile?.trustLevel ?? .bronze,
                            size: .small
                        )
                    }
                    Text("Tap to open Radar")
                        .font(DQ.Typography.caption())
                        .foregroundStyle(DQ.Colors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DQ.Colors.textQuaternary)
            }
            .padding(DQ.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DQ.Radii.large)
                    .fill(DQ.Colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DQ.Radii.large)
                            .stroke(DQ.Colors.accentOrange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .accessibilityLabel("A match is nearby. Tap to open radar.")
    }

    // MARK: - Helpers

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
