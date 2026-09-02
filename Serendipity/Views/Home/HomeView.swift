// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] BalanceEnforcer reads from Firestore (read-only on client)
// [x] Gender ratio badge displays aggregate data only — no PII
// [x] All match visibility gates enforced via MatchManager (community gate first,
//     then BalanceEnforcer for Dating-gated pairs only)
// [x] No sensitive user data exposed in UI — only display name and aggregate stats
// [x] Nearby signals stay blurred and unnamed — identity is gated behind an encounter
// [x] The only place name rendered is the school's own display name, and — inside a
//     live window — the destination's server-supplied label. No neighbourhood,
//     venue, building or geohash appears anywhere (DESIGN_SYSTEM.md §8).
// [x] Off campus the card says so and Quest Mode cannot be started from here
// [x] A lapsed Spring Break claim is surfaced, never silent. If presence stops
//     being refreshed the pool narrows to same-school, and the banner says so —
//     a user who believed they were still in the multi-school pool would
//     otherwise have no way to tell.
// [x] The gender-ratio chip is shown only when the user is Dating-gated, because
//     it describes a mechanism that does not apply to anyone else

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
                    springBreakBanner
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

            // The ratio drives Dating throttling and nothing else. Showing it to
            // someone on Study only would be describing a mechanism that has no
            // bearing on their experience.
            if balanceEnforcer.isStatsAvailable, isDatingGated { ratioChip }
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

    // MARK: - Spring Break

    /// Shown only when a destination claim has lapsed.
    ///
    /// Deliberately not a chip on the Quest card: the card describes what Quest
    /// Mode is doing, and this describes something that stopped. Sharing the
    /// slot would let one overwrite the other.
    @ViewBuilder
    private var springBreakBanner: some View {
        if let message = locationService.springBreakStatus.pausedMessage {
            HStack(alignment: .top, spacing: DQSpace.tight) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(p.text2)

                Text(message)
                    .font(DQFont.bodyS)
                    .foregroundStyle(p.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(DQSpace.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                    .strokeBorder(p.line, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
        }
    }

    // MARK: - Quest Card

    private var questCard: some View {
        let active = matchManager.isQuestModeActive
        let scope = locationService.communityScope
        return QuestCard(
            isActive: active && scope.allowsQuestMode,
            // §5's QuestCard assumes a quest content model (title, description,
            // `n / m quests`, an end time). This app has none — Quest Mode is a
            // scanning Bool. Copy describes what actually happens instead.
            title: questTitle(active: active, scope: scope),
            detail: questDetail(scope: scope),
            chips: questChips,
            onToggle: toggleQuestMode
        )
        .disabled(!scope.allowsQuestMode)
    }

    /// The card title carries the community, because that is the single most
    /// important fact about who you are about to see.
    ///
    /// "Quest Mode · UCLA" is community identity, which DESIGN_SYSTEM.md §8
    /// permits. A destination label like "Cancún · Spring Break" comes from the
    /// backend document, not from anything the device worked out about where the
    /// user is standing.
    private func questTitle(active: Bool, scope: CommunityScope) -> String {
        switch scope {
        case .none:
            return "Paused — you're off campus"
        case .campus:
            let school = authViewModel.currentUser?.schoolDisplayName
            let suffix = (school?.isEmpty == false) ? " · \(school!)" : ""
            return (active ? "Scanning\(suffix)" : "Start scanning\(suffix)")
        case .springBreak(_, let label):
            return active ? "Scanning · \(label)" : "Start scanning · \(label)"
        }
    }

    private func questDetail(scope: CommunityScope) -> String {
        switch scope {
        case .none:
            return "Quest Mode runs on campus. It'll pick back up when you're there."
        case .campus:
            return "You'll only see people from your school. An encounter opens "
                 + "when you're within \(rangeText) of someone compatible."
        case .springBreak:
            return "Here you'll see verified students from any school at this "
                 + "destination — not everyone on the beach."
        }
    }

    private var questChips: [String] {
        let scope = locationService.communityScope
        guard scope.allowsQuestMode else { return ["Off campus"] }

        var chips = ["Within \(rangeText)"]
        if scope.isSpringBreak { chips.append("Spring Break") }
        if locationService.prefersSquadRadar { chips.append("Squad Radar") }
        if matchManager.isQuestModeActive {
            chips.append("\(matchManager.nearbyUsers.count) nearby")
        }
        return chips
    }

    private func toggleQuestMode(_ active: Bool) {
        // Off campus there is no pool to scan, so there is nothing to turn on.
        // The card is already disabled; this is the second guard.
        guard locationService.communityScope.allowsQuestMode else { return }

        if active, let user = authViewModel.currentUser {
            // Gates run inside enableQuestMode: student ID verification, then the
            // campus geofence, then the caps and balance layers for Dating pairs.
            matchManager.enableQuestMode(for: user)
        } else {
            matchManager.disableQuestMode()
        }
    }

    /// Whether Dating's machinery applies to this user right now — Dating on, or
    /// inside the server-written 24h cooldown that follows switching it off.
    private var isDatingGated: Bool {
        authViewModel.currentUser?.isDatingGated() ?? false
    }

    // MARK: - Signals Nearby

    @ViewBuilder
    private var signalsSection: some View {
        let signals = Array(matchManager.nearbyUsers.prefix(2))
        if !locationService.communityScope.allowsQuestMode {
            // When a Spring Break claim has lapsed the banner above already
            // explains the pause, so this states the consequence without
            // repeating the cause.
            DQEmptyState(
                symbol: "pause.circle",
                title: "Quest Mode is paused",
                message: locationService.springBreakStatus.pausedMessage == nil
                    ? "You're outside your campus. Nothing is scanning, and nobody can see you."
                    : "Nothing is scanning, and nobody can see you."
            )
            .padding(.top, DQSpace.block)
        } else if !signals.isEmpty {
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
                                vibeScore: vibeScore(for: user),
                                school: user.schoolDisplayName
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
