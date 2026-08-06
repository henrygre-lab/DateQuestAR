// MARK: - Vibe Coding Security Checklist Compliance
// [x] No hardcoded secrets, API keys, or tokens
// [x] BalanceEnforcer reads from Firestore (read-only on client)
// [x] Gender ratio badge displays aggregate data only — no PII
// [x] All match visibility gates enforced via BalanceEnforcer.shouldShowMatch
// [x] No sensitive user data exposed in UI — only display name and aggregate stats
// [x] Nearby signals stay blurred and unnamed — identity is gated behind an encounter

import SwiftUI

private enum HomeTab: Hashable { case home, stats, settings }

/// DesignSystem v2 skin (docs/DESIGN_SYSTEM.md §5, §6 row 1): header →
/// QuestCard → DemoControl (DEBUG) → nearby signals, over a floating pill tab
/// bar. Quest-mode wiring, the balance gate and the demo entry point are
/// unchanged; only the presentation moved.
struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var matchManager: MatchManager
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var balanceEnforcer: BalanceEnforcer
    @Environment(\.dq) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: HomeTab = .home
    @State private var showRadar = false

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
                .toolbar(.hidden, for: .tabBar)
                .tag(HomeTab.home)

            StatsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(HomeTab.stats)

            SettingsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(HomeTab.settings)
        }
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(
                items: [
                    .init(tab: .home, symbol: "location.north.circle.fill", label: "Quest"),
                    .init(tab: .stats, symbol: "chart.bar.fill", label: "Stats"),
                    .init(tab: .settings, symbol: "gearshape.fill", label: "Settings")
                ],
                selection: $selectedTab
            )
        }
        .fullScreenCover(isPresented: $showRadar) {
            RadarView()
        }
        #if DEBUG
        .fullScreenCover(isPresented: $matchManager.isDemoEncounterActive) {
            EncounterView()
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .matchAlertTapped)) { _ in
            showRadar = true
        }
    }

    // MARK: - Dashboard

    private var dashboardTab: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DQSpace.gutter) {
                    header
                    questCard
                    #if DEBUG
                    DemoControl(
                        onSimulate: startDemo,
                        onReset: { matchManager.endDemoEncounter() }
                    )
                    if let message = matchManager.demoStatusMessage {
                        demoStatusBanner(message)
                            .task(id: message) {
                                try? await Task.sleep(nanoseconds: 5_000_000_000)
                                matchManager.demoStatusMessage = nil
                            }
                    }
                    #endif
                    signalsSection
                }
                .padding(.horizontal, DQSpace.gutter)
                .padding(.top, DQSpace.safeTop)
                .padding(.bottom, DQSpace.gutter)
            }
            // Signal cards pass under the glass tab bar. The soft edge fades
            // them into it instead of letting a hard card corner cut across the
            // material.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        // §3: the 58 is measured from the physical top edge.
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DQSpace.tight) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(DQFont.displayM)
                    .tracking(DQFont.trackDisplayM)
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(signalSummary)
                    .font(DQFont.labelSized(11, .semibold))
                    .tracking(DQFont.track(11, em: 0.14))
                    .textCase(.uppercase)
                    .foregroundStyle(p.text2)
            }

            Spacer(minLength: 0)

            if balanceEnforcer.isStatsAvailable { ratioChip }
            avatarMenu
        }
        .accessibilityElement(children: .contain)
    }

    /// Aggregate balance signal. Escalates by contrast, not hue — ember stays
    /// reserved for progress and commitment.
    private var ratioChip: some View {
        let femalePct = Int((1.0 - balanceEnforcer.currentRatio) * 100)
        let malePct = Int(balanceEnforcer.currentRatio * 100)
        return Text("\(femalePct):\(malePct)")
            .font(DQFont.monoSized(10, .medium))
            .foregroundStyle(balanceEnforcer.needsFemaleBoost ? p.text : p.text3)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(p.surface2))
            .overlay(Capsule().strokeBorder(p.line, lineWidth: 1))
            .accessibilityLabel("Gender ratio: \(femalePct) percent female, \(malePct) percent male")
    }

    private var avatarMenu: some View {
        Menu {
            Button(role: .destructive) { authViewModel.signOut() } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Text(displayName.dqInitials)
                .font(DQFont.uiSized(15, .bold))
                .foregroundStyle(p.text2)
                .frame(width: DQSize.minHitTarget, height: DQSize.minHitTarget)
                .background(Circle().fill(p.surface2))
                .overlay(Circle().strokeBorder(p.ember, lineWidth: 2))
        }
        .accessibilityLabel("Account menu for \(displayName)")
    }

    // MARK: - Quest Card

    private var questCard: some View {
        let active = matchManager.isQuestModeActive
        return QuestCard(
            isActive: active,
            // §5's QuestCard assumes a quest content model (title, description,
            // `n / m quests`, an end time). This app has none — Quest Mode is a
            // scanning Bool. Copy describes what actually happens instead.
            title: active ? "Scanning for someone nearby" : "Start scanning nearby",
            detail: "An encounter opens when you're within \(rangeText) of a compatible match.",
            chips: questChips,
            onToggle: toggleQuestMode
        )
    }

    private var questChips: [String] {
        var chips = ["Within \(rangeText)"]
        if matchManager.isQuestModeActive {
            chips.append("\(matchManager.nearbyUsers.count) nearby")
        }
        return chips
    }

    private func toggleQuestMode(_ active: Bool) {
        if active, let user = authViewModel.currentUser {
            // Phase 2 safety wiring — centralized gender-balance + alert caps
            // (enableQuestMode internally calls AlertCapManager.updateUserCaps
            //  and BalanceEnforcer gating before any proximity event fires)
            matchManager.enableQuestMode(for: user)
        } else {
            matchManager.disableQuestMode()
        }
    }

    // MARK: - Signals Nearby

    @ViewBuilder
    private var signalsSection: some View {
        let signals = Array(matchManager.nearbyUsers.prefix(2))
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Signals nearby")
                        .font(DQFont.titleS)
                        .tracking(DQFont.track(16, em: -0.015))
                        .foregroundStyle(p.text)

                    Spacer(minLength: 0)

                    Button { showRadar = true } label: {
                        Text("See all")
                            .font(DQFont.uiSized(11, .semibold))
                            .foregroundStyle(p.text2)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: DQSize.minHitTarget)
                    .accessibilityLabel("See all nearby signals")
                }

                HStack(spacing: 11) {
                    ForEach(signals, id: \.uid) { user in
                        Button { showRadar = true } label: {
                            SignalCard(
                                name: user.displayName,
                                tier: user.trustLevel,
                                vibeScore: vibeScore(for: user)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Joins a nearby profile to its match record, when one exists — the score
    /// lives on `Match`, not on the profile.
    private func vibeScore(for user: UserProfile) -> Double? {
        matchManager.activeMatches
            .first { $0.userAUID == user.uid || $0.userBUID == user.uid }?
            .compatibilityScore
    }

    // MARK: - Demo (DEBUG only)

    #if DEBUG
    /// Portfolio walkthrough trigger. Simulates a compatible match walking up so
    /// the full proximity → reveal → icebreaker → NameDrop flow can be demoed
    /// with no location/UWB hardware and no backend.
    private func startDemo() {
        guard let user = authViewModel.currentUser else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        matchManager.startDemoEncounter(for: user)
    }

    /// Explains when the safety gates (alert caps, women-first queue,
    /// compatibility) prevented a demo match from surfacing.
    private func demoStatusBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DQSpace.tight) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.text3)
            Text(message)
                .font(DQFont.bodyS)
                .foregroundStyle(p.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DQSpace.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.thumb, style: .continuous)
                .fill(p.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.thumb, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .transition(.opacity)
        .accessibilityLabel(message)
    }
    #endif

    // MARK: - Helpers

    private var displayName: String {
        authViewModel.currentUser?.displayName ?? "Quester"
    }

    private var greeting: String {
        let first = displayName.split(separator: " ").first.map(String.init) ?? displayName
        return "\(timeOfDay), \(first)"
    }

    private var timeOfDay: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  "Morning"
        case 12..<17: "Afternoon"
        case 17..<22: "Evening"
        default:      "Late night"
        }
    }

    /// The mock pairs this with a neighbourhood name. Naming the user's
    /// neighbourhood on the home screen is exactly the location exposure the
    /// product avoids, so only the count ships.
    private var signalSummary: String {
        let count = matchManager.nearbyUsers.count
        guard count > 0 else { return "No signals near" }
        return "\(count) signal\(count == 1 ? "" : "s") near"
    }

    private var rangeText: String {
        let miles = authViewModel.currentUser?.preferences.maxDistanceMiles ?? 0.25
        return String(format: "%.2g mi", miles)
    }
}
